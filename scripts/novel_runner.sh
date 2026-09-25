#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p logs

PRIMARY="${NOVEL_MODEL:-opencode/space-bunny-free}"
FALLBACKS="${NOVEL_FALLBACK_MODELS:-opencode/muse-spark-1.3-contributor-free,opencode/muse-spark-1.2-contributor-free,opencode/nemotron-3-ultra-free,opencode/nemotron-3.5-lightning-free,opencode/mimo-v2.6-flash-free,opencode/ling-3.0-flash-fin-free}"
MAX_MODELS="${MAX_MODELS:-3}"
PLANNING_TIMEOUT_SECONDS="${PLANNING_TIMEOUT_SECONDS:-2700}"
BATCH_TIMEOUT_SECONDS="${BATCH_TIMEOUT_SECONDS:-7200}"
REVIEW_TIMEOUT_SECONDS="${REVIEW_TIMEOUT_SECONDS:-900}"
FIX_TIMEOUT_SECONDS="${FIX_TIMEOUT_SECONDS:-3600}"
CHECKPOINT_INTERVAL_SECONDS="${CHECKPOINT_INTERVAL_SECONDS:-300}"

if [ -z "${OPENCODE_API_KEY:-}" ]; then
  echo "OPENCODE_API_KEY is missing" >&2
  exit 2
fi

# state/phase-ledger.json is the controller's authority. Writer prompts may
# update story state, but they must not claim or mark a phase complete.
ledger_file="state/phase-ledger.json"
if [ ! -f "$ledger_file" ]; then
  echo "Controller ledger is missing: $ledger_file" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "Controller requires jq to update $ledger_file" >&2
  exit 1
fi

ledger_key_for_dir() {
  local candidate_dir="$1"
  case "$candidate_dir" in
    workspace/volume-*/batch-*) printf '%s\n' "${candidate_dir#workspace/}" | tr '/' '-' ;;
    *) basename "$candidate_dir" ;;
  esac
}

ledger_phase_id="$(jq -r '.currentPhase // empty' "$ledger_file")"
phase_dir=""
while IFS= read -r prompt_file; do
  candidate="$(dirname "$prompt_file")"
  candidate_key="$(ledger_key_for_dir "$candidate")"
  candidate_status="$(jq -r --arg id "$candidate_key" '(.phases // []) | map(select(.id == $id)) | .[0].status // "planned"' "$ledger_file")"
  if [ "$candidate_status" = "done" ] || [ -f "$candidate/.blocked" ]; then
    continue
  fi
  if [ -z "$phase_dir" ] && [ "$candidate_key" = "$ledger_phase_id" ]; then
    phase_dir="$candidate"
    break
  fi
  if [ -z "$phase_dir" ]; then
    phase_dir="$candidate"
  fi
done < <(find workspace -name PROMPT.md -type f | sort)

if [ -z "$phase_dir" ]; then
  echo "No incomplete phase found"
  exit 0
fi

phase_id="$(basename "$phase_dir")"
ledger_phase_key="$(ledger_key_for_dir "$phase_dir")"
prompt_file="$phase_dir/PROMPT.md"
log_file="logs/${phase_id}.log"
review_log="logs/${phase_id}.review.log"
fix_log="logs/${phase_id}.fix.log"
wip_branch="novel-wip/${phase_id}"
checkpoint_pid=""

case "$phase_id" in
  phase-000-*|phase-001-*|phase-002-*) phase_timeout="$PLANNING_TIMEOUT_SECONDS" ;;
  *) phase_timeout="$BATCH_TIMEOUT_SECONDS" ;;
esac

printf '%s\n' "Running $phase_id with timeout ${phase_timeout}s" | tee "$log_file"

start_checkpoint_loop() {
  checkpoint_loop &
  checkpoint_pid=$!
}

stop_checkpoint_loop() {
  if [ -n "$checkpoint_pid" ]; then
    kill "$checkpoint_pid" 2>/dev/null || true
    wait "$checkpoint_pid" 2>/dev/null || true
    checkpoint_pid=""
  fi
}

checkpoint_wip() {
  if ! git status --porcelain 2>/dev/null | grep -vE '^\?\? logs/|^.. logs/' | grep -q .; then
    return 0
  fi
  git add -A 2>/dev/null || true
  local tree commit base
  tree="$(git write-tree 2>/dev/null)" || return 0
  base="$(git rev-parse HEAD 2>/dev/null || echo HEAD)"
  commit="$(git commit-tree "$tree" -p "$base" -m "novel: checkpoint $phase_id $(date -u +%s)" 2>/dev/null)" || return 0
  if git push origin "$commit:refs/heads/$wip_branch" --force 2>/dev/null; then
    echo "Checkpoint pushed to $wip_branch"
  fi
  git reset -q 2>/dev/null || true
}

checkpoint_loop() {
  while true; do
    sleep "$CHECKPOINT_INTERVAL_SECONDS"
    checkpoint_wip || true
  done
}

resume_wip() {
  if git ls-remote --exit-code origin "refs/heads/$wip_branch" >/dev/null 2>&1; then
    echo "Resuming checkpoint from $wip_branch"
    git fetch origin "$wip_branch" 2>/dev/null || true
    git merge --no-edit FETCH_HEAD
    touch "$phase_dir/.checkpoint"
    rm -f "$phase_dir/.deferred"
  fi
}

clear_wip() {
  git push origin --delete "$wip_branch" 2>/dev/null || true
  rm -f "$phase_dir/.checkpoint"
}

commit_changes() {
  local message="$1"
  git config user.name "novel-fleet-bot"
  git config user.email "novel-fleet-bot@users.noreply.github.com"
  git add -A
  if git diff --cached --quiet; then
    return 1
  fi
  git commit -m "$message"
  git push origin HEAD
  return 0
}

# The controller alone records phase status. The writer only changes story
# state; these calls keep the authoritative ledger in step with the run.
ledger_mark() {
  local status="$1"
  local attempts_value="$2"
  local model_value="${3:-}"
  local fallback_value="${4:-false}"
  local range_value="${5:-null}"
  local result_value="${6:-}"
  local base_value="${7:-}"
  local lease_value="${8:-}"
  local tmp
  tmp="$(mktemp)"
  jq \
    --arg id "$ledger_phase_key" \
    --arg status "$status" \
    --argjson attempts "$attempts_value" \
    --arg model "$model_value" \
    --arg fallback "$fallback_value" \
    --arg range "$range_value" \
    --arg result "$result_value" \
    --arg base "$base_value" \
    --arg lease "$lease_value" '
      ((.phases // []) | map(select(.id == $id)) | .[0] // {}) as $existing
      | .currentPhase = $id
      | .phases = ((.phases // []) | map(select(.id != $id))) + [
          ({
            id: $id,
            status: $status,
            fallbackUsed: (if $model == "" and $fallback == "false" then ($existing.fallbackUsed // false) else ($fallback == "true") end),
            range: (if $range == "" or $range == "null" then ($existing.range // null) else $range end),
            attempts: $attempts,
            actualModel: (if $model == "" then ($existing.actualModel // null) else $model end),
            baseCommit: (if $base == "" then ($existing.baseCommit // null) else $base end),
            leaseExpiry: (if $lease == "" then ($existing.leaseExpiry // null) else $lease end),
            nextRetryTime: ($existing.nextRetryTime // null)
          } + (if $result == "" then {} else {resultCommit: $result} end))
        ]
    ' "$ledger_file" >"$tmp" && mv "$tmp" "$ledger_file"
}

ledger_current_attempts() {
  jq -r --arg id "$ledger_phase_key" '(.phases // []) | map(select(.id == $id)) | .[0].attempts // 0' "$ledger_file"
}

checkpoint_and_defer() {
  local reason="$1"
  ledger_mark deferred "$attempts" "$actual_model" "$fallback_used" "$phase_range" || true
  stop_checkpoint_loop
  touch "$phase_dir/.checkpoint" "$phase_dir/.deferred"
  checkpoint_wip
  echo "Phase deferred: $phase_id ($reason)"
  exit 0
}

block_phase() {
  local reason="$1"
  ledger_mark blocked "$attempts" "$actual_model" "$fallback_used" "$phase_range" || true
  stop_checkpoint_loop
  touch "$phase_dir/.blocked"
  commit_changes "novel: block $phase_id ($reason)" || true
  echo "Phase blocked: $phase_id ($reason)"
  exit 1
}

model_list=("$PRIMARY")
IFS=',' read -r -a fallback_list <<< "$FALLBACKS"
for model in "${fallback_list[@]}"; do
  [ -n "$model" ] && model_list+=("$model")
done
if [ "${#model_list[@]}" -gt "$MAX_MODELS" ]; then
  model_list=("${model_list[@]:0:$MAX_MODELS}")
fi

resume_wip
prompt_text="$(cat "$prompt_file")"
if [ -f "$phase_dir/.checkpoint" ]; then
  prompt_text="A checkpoint exists for this phase. Continue from the existing files and state. Do not restart completed work. $prompt_text"
fi

# A batch phase is a single writer execution. If its declared range is
# already on disk, skip the writer but continue through review, fixes, and
# the controller ledger instead of exiting before those steps.
batch_complete=false
batch_start=""
batch_end=""
phase_range="null"
if [[ "$phase_dir" == workspace/volume-*/batch-* ]] && [[ "$prompt_text" =~ Chapters[[:space:]]+([0-9]+)[–-]([0-9]+) ]]; then
  batch_start="${BASH_REMATCH[1]}"
  batch_end="${BASH_REMATCH[2]}"
  phase_range="${batch_start}-${batch_end}"
  volume_name="$(basename "$(dirname "$phase_dir")")"
  batch_complete=true
  for ((chapter=batch_start; chapter<=batch_end; chapter++)); do
    chapter_file="$ROOT/chapters/$volume_name/chapter-$(printf '%04d' "$chapter").md"
    if [ ! -f "$chapter_file" ]; then
      batch_complete=false
      break
    fi
  done
  if [ "$batch_complete" = true ]; then
    echo "Batch already complete: $phase_id (chapters $batch_start-$batch_end)"
  fi
fi

attempts="$(ledger_current_attempts)"
case "$attempts" in
  ''|*[!0-9]*) attempts=0 ;;
esac
attempts=$((attempts + 1))
actual_model=""
fallback_used=false
base_commit="$(git rev-parse HEAD)"
lease_expiry="$(date -u -d '+4 hours' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)"
ledger_mark running "$attempts" "$actual_model" "$fallback_used" "$phase_range" "" "$base_commit" "$lease_expiry"

if [ "$batch_complete" = true ]; then
  writer_ok=true
else
  start_checkpoint_loop
  writer_ok=false
  attempted=0
  for model in "${model_list[@]}"; do
    attempted=$((attempted + 1))
    printf 'Trying writer model %s\n' "$model" | tee -a "$log_file"
    set +e
    timeout --signal=TERM --kill-after=30s "$phase_timeout" opencode run --model "$model" --agent novel-writer "$prompt_text" >>"$log_file" 2>&1
    code=$?
    set -e
    if [ "$code" -eq 0 ]; then
      printf 'Writer model used: %s\n' "$model" | tee -a "$log_file"
      actual_model="$model"
      [ "$model" = "$PRIMARY" ] || fallback_used=true
      writer_ok=true
      break
    fi
    if [ "$code" -eq 124 ] || [ "$code" -eq 143 ]; then
      checkpoint_and_defer "writer timeout"
    fi
    if grep -qiE '429|rate limit|too many requests|quota|timeout|timed out|502|503|504|model not found|unavailable' "$log_file"; then
      printf 'Writer model unavailable or rate limited: %s\n' "$model" | tee -a "$log_file"
      if [ "$attempted" -ge "$MAX_MODELS" ]; then
        checkpoint_and_defer "all writer models unavailable"
      fi
      continue
    fi
    printf 'Writer failed with a work error; not switching models.\n' | tee -a "$log_file"
    actual_model="$model"
    fallback_used=true
    block_phase "writer work error"
  done
  stop_checkpoint_loop
  if [ "$writer_ok" != true ]; then
    checkpoint_and_defer "no writer model succeeded"
  fi
fi

if ! git diff --quiet; then
  if ! commit_changes "novel: save writer work $phase_id"; then
    echo "Writer produced no file changes; deferring"
    ledger_mark deferred "$attempts" "$actual_model" "$fallback_used" "$phase_range" || true
    touch "$phase_dir/.deferred"
    exit 0
  fi
elif [ "$batch_complete" != true ]; then
  echo "Writer exited successfully but produced no file changes; deferring"
  ledger_mark deferred "$attempts" "$actual_model" "$fallback_used" "$phase_range" || true
  touch "$phase_dir/.deferred"
  exit 0
fi


start_checkpoint_loop
set +e
timeout --signal=TERM --kill-after=20s "$REVIEW_TIMEOUT_SECONDS" opencode run --model "$PRIMARY" --agent novel-reviewer "Review the current phase changes. Do not edit files. Return concrete findings and finish promptly." >"$review_log" 2>&1
review_code=$?
set -e
stop_checkpoint_loop

if [ "$review_code" -eq 124 ] || [ "$review_code" -eq 143 ]; then
  echo "Review timed out; writer work is already committed"
  ledger_mark deferred "$attempts" "$actual_model" "$fallback_used" "$phase_range" || true
  touch "$phase_dir/.deferred"
  exit 0
fi

if [ "$review_code" -ne 0 ]; then
  block_phase "review failed"
fi

if [ "$review_code" -eq 0 ] && grep -qiE 'finding|problem|issue|contradiction|repetition|outline-like|meta' "$review_log"; then
  start_checkpoint_loop
  set +e
  timeout --signal=TERM --kill-after=20s "$FIX_TIMEOUT_SECONDS" opencode run --model "$PRIMARY" --agent novel-writer "Read the reviewer findings in $review_log. Apply necessary fixes to the current phase and state files. Preserve good prose, do not restart the batch, and do not change the planned plot." >"$fix_log" 2>&1
  fix_code=$?
  set -e
  stop_checkpoint_loop
  if [ "$fix_code" -eq 124 ] || [ "$fix_code" -eq 143 ]; then
    checkpoint_and_defer "fix timeout"
  fi
  if [ "$fix_code" -ne 0 ]; then
    block_phase "review fix failed"
  fi
  commit_changes "novel: save review fixes $phase_id" || true
fi

ledger_mark done "$attempts" "$actual_model" "$fallback_used" "$phase_range"
touch "$phase_dir/.done"
rm -f "$phase_dir/.deferred" "$phase_dir/.blocked" "$phase_dir/.checkpoint"
if ! commit_changes "novel: complete $phase_id"; then
  echo "Completion marker produced no commit"
  exit 0
fi
ledger_mark done "$attempts" "$actual_model" "$fallback_used" "$phase_range" "$(git rev-parse HEAD)"
commit_changes "novel: record phase result $phase_id" || true
clear_wip

if [ -n "${GH_TOKEN:-}" ]; then
  gh api -X POST \
    -H "Accept: application/vnd.github+json" \
    "repos/${GITHUB_REPOSITORY}/dispatches" \
    -f event_type=novel_tick \
    -f "client_payload[phase]=${phase_id}" \
    -f "client_payload[run_id]=${GITHUB_RUN_ID:-local}"
fi

echo "Completed $phase_id"
