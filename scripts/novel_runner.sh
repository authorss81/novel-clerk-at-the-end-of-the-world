#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p logs

PRIMARY="${NOVEL_MODEL:-opencode/space-bunny-free}"
FALLBACKS="${NOVEL_FALLBACK_MODELS:-opencode/muse-spark-1.3-contributor-free,opencode/muse-spark-1.2-contributor-free,opencode/nemotron-3-ultra-free,opencode/nemotron-3.5-lightning-free,opencode/mimo-v2.6-flash-free,opencode/ling-3.0-flash-fin-free}"
MAX_MODELS="${MAX_MODELS:-3}"

if [ -z "${OPENCODE_API_KEY:-}" ]; then
  echo "OPENCODE_API_KEY is missing" >&2
  exit 2
fi

phase_dir=""
while IFS= read -r prompt_file; do
  candidate="$(dirname "$prompt_file")"
  if [ ! -f "$candidate/.done" ] && [ ! -f "$candidate/.blocked" ]; then
    phase_dir="$candidate"
    break
  fi
done < <(find workspace -name PROMPT.md -type f | sort)

if [ -z "$phase_dir" ]; then
  echo "No incomplete phase found"
  exit 0
fi

phase_id="$(basename "$phase_dir")"
prompt_file="$phase_dir/PROMPT.md"
log_file="logs/${phase_id}.log"
review_log="logs/${phase_id}.review.log"
fix_log="logs/${phase_id}.fix.log"
phase_timeout="${PHASE_TIMEOUT_SECONDS:-5400}"

case "$phase_id" in
  phase-000-*|phase-001-*|phase-002-*) phase_timeout="${PLANNING_TIMEOUT_SECONDS:-1800}" ;;
esac

printf '%s\n' "Running $phase_id with timeout ${phase_timeout}s" | tee "$log_file"

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

checkpoint_and_defer() {
  local reason="$1"
  touch "$phase_dir/.checkpoint"
  if commit_changes "novel: checkpoint $phase_id"; then
    echo "Checkpoint saved for $phase_id"
  fi
  touch "$phase_dir/.deferred"
  echo "Phase deferred: $phase_id ($reason)"
  exit 0
}

model_list=("$PRIMARY")
IFS=',' read -r -a fallback_list <<< "$FALLBACKS"
for model in "${fallback_list[@]}"; do
  [ -n "$model" ] && model_list+=("$model")
done
if [ "${#model_list[@]}" -gt "$MAX_MODELS" ]; then
  model_list=("${model_list[@]:0:$MAX_MODELS}")
fi

prompt_text="$(cat "$prompt_file")"
if [ -f "$phase_dir/.checkpoint" ]; then
  prompt_text="A checkpoint exists for this phase. Continue from the existing files and state. Do not restart completed work. $prompt_text"
fi

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
  touch "$phase_dir/.blocked"
  exit 1
done

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
  echo "Writer exited successfully but produced no file changes; deferring"
  touch "$phase_dir/.deferred"
  exit 0
fi

set +e
timeout --signal=TERM --kill-after=20s 900s opencode run --model "$PRIMARY" --agent novel-reviewer "Review the current phase changes. Do not edit files. Return concrete findings and finish promptly." >"$review_log" 2>&1
review_code=$?
set -e

if [ "$review_code" -eq 124 ] || [ "$review_code" -eq 143 ]; then
  echo "Review timed out; writer checkpoint is already saved"
  touch "$phase_dir/.deferred"
  exit 0
fi

if [ "$review_code" -eq 0 ] && grep -qiE 'finding|problem|issue|contradiction|repetition|outline-like|meta' "$review_log"; then
  set +e
  timeout --signal=TERM --kill-after=20s 3600s opencode run --model "$PRIMARY" --agent novel-writer "Read the reviewer findings in $review_log. Apply necessary fixes to the current phase and state files. Preserve good prose, do not restart the batch, and do not change the planned plot." >"$fix_log" 2>&1
  fix_code=$?
  set -e
  if [ "$fix_code" -eq 124 ] || [ "$fix_code" -eq 143 ]; then
    echo "Fix pass timed out; writer checkpoint is already saved"
    touch "$phase_dir/.deferred"
    exit 0
  fi
  if [ "$fix_code" -ne 0 ]; then
    touch "$phase_dir/.blocked"
    exit 1
  fi
  commit_changes "novel: save review fixes $phase_id" || true
fi

touch "$phase_dir/.done"
rm -f "$phase_dir/.deferred" "$phase_dir/.blocked" "$phase_dir/.checkpoint"
if ! commit_changes "novel: complete $phase_id"; then
  echo "Completion marker produced no commit"
  exit 0
fi

if [ -n "${GH_TOKEN:-}" ]; then
  gh api -X POST \
    -H "Accept: application/vnd.github+json" \
    "repos/${GITHUB_REPOSITORY}/dispatches" \
    -f event_type=novel_tick \
    -f "client_payload[phase]=${phase_id}" \
    -f "client_payload[run_id]=${GITHUB_RUN_ID:-local}"
fi

echo "Completed $phase_id"
