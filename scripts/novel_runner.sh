#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
git config user.name "novel-fleet-bot"
git config user.email "novel-fleet-bot@users.noreply.github.com"
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

phase_dir=""
retired_changed=false
while IFS= read -r prompt_file; do
  candidate="$(dirname "$prompt_file")"
  if [ -f "$candidate/.retired" ]; then
    continue
  fi
  if grep -qi '^Retired .*phase' "$prompt_file"; then
    touch "$candidate/.retired"
    retired_changed=true
    continue
  fi
  if [ ! -f "$candidate/.done" ] && [ ! -f "$candidate/.blocked" ]; then
    phase_dir="$candidate"
    break
  fi
done < <(find workspace -name PROMPT.md -type f | sort)
if [ "$retired_changed" = true ]; then
  git add workspace
  git commit -m "novel: retire obsolete planning phases" >/dev/null
  git push origin HEAD
fi

if [ -z "$phase_dir" ]; then
  echo "No incomplete phase found"
  exit 0
fi

phase_id="$(basename "$phase_dir")"
prompt_file="$phase_dir/PROMPT.md"
log_file="logs/${phase_id}.log"
review_log="logs/${phase_id}.review.log"
fix_log="logs/${phase_id}.fix.log"
wip_branch="novel-wip/${phase_id}"
checkpoint_pid=""
resumed_work=false

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
  if [ -f "$phase_dir/.wip-conflict" ]; then
    echo "Skipping stale WIP branch $wip_branch after a previous merge conflict"
    return 0
  fi
  if git ls-remote --exit-code origin "refs/heads/$wip_branch" >/dev/null 2>&1; then
    echo "Resuming checkpoint from $wip_branch"
    git fetch origin "$wip_branch" 2>/dev/null || true
    if ! git merge --no-edit FETCH_HEAD; then
      git merge --abort 2>/dev/null || true
      touch "$phase_dir/.wip-conflict"
      git add "$phase_dir/.wip-conflict"
      git commit -m "novel: skip stale WIP $phase_id" >/dev/null
      git push origin HEAD
      echo "WIP conflict; continuing from current main"
      return 0
    fi
    if ! git diff --quiet origin/main..HEAD; then
      resumed_work=true
    fi
    touch "$phase_dir/.checkpoint"
    rm -f "$phase_dir/.deferred"
  fi
}

clear_wip() {
  git push origin --delete "$wip_branch" 2>/dev/null || true
  rm -f "$phase_dir/.checkpoint"
}

restore_controller_files() {
  git restore --source=HEAD -- \
    scripts/novel_runner.sh \
    .github/workflows/novels.yml \
    .opencode/agent/novel-writer.md \
    .opencode/agent/novel-reviewer.md \
    AGENTS.md PHASE_SYSTEM.md REPO_PLAN.md OUTLINE_GUIDE.md opencode.json 2>/dev/null || true
}

commit_changes() {
  local message="$1"
  git config user.name "novel-fleet-bot"
  git config user.email "novel-fleet-bot@users.noreply.github.com"
  restore_controller_files
  git add -A
  if git diff --cached --quiet; then
    return 1
  fi
  git commit -m "$message"
  git push origin HEAD
  return 0
}

checkpoint_and_defer() {
  local reason="$1"
  stop_checkpoint_loop
  touch "$phase_dir/.checkpoint" "$phase_dir/.deferred"
  checkpoint_wip
  echo "Phase deferred: $phase_id ($reason)"
  exit 0
}

has_other_incomplete_phase() {
  local candidate
  while IFS= read -r prompt_file; do
    candidate="$(dirname "$prompt_file")"
    if [ "$candidate" != "$phase_dir" ] && [ ! -f "$candidate/.retired" ] && [ ! -f "$candidate/.done" ] && [ ! -f "$candidate/.blocked" ]; then
      return 0
    fi
  done < <(find workspace -name PROMPT.md -type f | sort)
  return 1
}

next_continuation_dir() {
  local candidate="workspace/continuation/next"
  if [ -f "$candidate/.done" ] || [ -f "$candidate/.blocked" ]; then
    local n=1
    while :; do
      candidate="$(printf 'workspace/continuation/next-%04d' "$n")"
      [ -e "$candidate" ] || break
      n=$((n + 1))
    done
  fi
  printf '%s\n' "$candidate"
}

ensure_next_phase() {
  if has_other_incomplete_phase; then
    return 0
  fi
  local continuation_dir
  continuation_dir="$(next_continuation_dir)"
  mkdir -p "$continuation_dir"
  cat > "$continuation_dir/PROMPT.md" <<EOF
Continue the novel after the completed phase $phase_id.

Read NOVEL_SPEC.md, the series outline and ending, the relevant volume outline, state/current.md, the rolling summaries, and the previous 20 chapters before writing. If the current volume is complete, plan the next volume and write its first 10 to 20 chapter batch. Otherwise write the next planned batch. Do not stop at an outline. Update manuscript state files and create exactly one next phase prompt before this phase is marked done. Do not edit controller, workflow, agent, or dispatcher files.
EOF
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
  stop_checkpoint_loop
  touch "$phase_dir/.blocked"
  exit 1
done
stop_checkpoint_loop

if [ "$writer_ok" != true ]; then
  checkpoint_and_defer "no writer model succeeded"
fi

if ! git diff --quiet; then
  if ! commit_changes "novel: save writer work $phase_id"; then
    echo "Writer produced no file changes; deferring"
    touch "$phase_dir/.deferred"
    exit 0
  fi
else
  if [ "$resumed_work" = true ]; then
    echo "Writer returned no new changes; promoting resumed WIP commit"
    git push origin HEAD:main
  else
    echo "Writer exited successfully but produced no file changes; deferring"
    touch "$phase_dir/.deferred"
    exit 0
  fi
fi

start_checkpoint_loop
set +e
timeout --signal=TERM --kill-after=20s "$REVIEW_TIMEOUT_SECONDS" opencode run --model "$PRIMARY" --agent novel-reviewer "Review the current phase changes. Do not edit files. Return concrete findings and finish promptly." >"$review_log" 2>&1
review_code=$?
set -e
stop_checkpoint_loop

if [ "$review_code" -eq 124 ] || [ "$review_code" -eq 143 ]; then
  echo "Review timed out; writer work is already committed"
  touch "$phase_dir/.deferred"
  exit 0
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
    touch "$phase_dir/.blocked"
    exit 1
  fi
  commit_changes "novel: save review fixes $phase_id" || true
fi

ensure_next_phase
touch "$phase_dir/.done"
rm -f "$phase_dir/.deferred" "$phase_dir/.blocked" "$phase_dir/.checkpoint" "$phase_dir/.wip-conflict"
if ! commit_changes "novel: complete $phase_id"; then
  echo "Completion marker produced no commit"
  exit 0
fi
clear_wip

if [ "${DISABLE_DIRECT_DISPATCH:-0}" != "1" ] && [ -n "${GH_TOKEN:-}" ]; then
  gh api -X POST \
    -H "Accept: application/vnd.github+json" \
    "repos/${GITHUB_REPOSITORY}/dispatches" \
    -f event_type=novel_tick \
    -f "client_payload[phase]=${phase_id}" \
    -f "client_payload[run_id]=${GITHUB_RUN_ID:-local}"
fi

echo "Completed $phase_id"
