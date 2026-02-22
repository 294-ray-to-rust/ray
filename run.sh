#!/usr/bin/env bash
set -euo pipefail

# ===========================================================================
# ray-agents orchestrator
#
# Runs a loop: Manager creates issues -> SWE implements them -> repeat
#
# Usage:
#   ./run.sh                                    # Defaults: 5 cycles, 3 SWE runs each
#   ./run.sh --max-cycles 10                    # 10 manager cycles
#   ./run.sh --swe-runs-per-cycle 5             # 5 SWE runs between manager runs
# ===========================================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# ---------------------------------------------------------------------------
# Configuration (overridable via flags)
# ---------------------------------------------------------------------------
MAX_CYCLES=5
SWE_RUNS_PER_CYCLE=3

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-cycles)
      MAX_CYCLES="$2"
      shift 2
      ;;
    --swe-runs-per-cycle)
      SWE_RUNS_PER_CYCLE="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [--max-cycles N] [--swe-runs-per-cycle N]"
      echo ""
      echo "Options:"
      echo "  --max-cycles N           Number of manager/SWE cycles (default: 5)"
      echo "  --swe-runs-per-cycle N   SWE agent runs per cycle (default: 3)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
LOG_DIR="$PROJECT_DIR/.opencode/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$LOG_DIR"

# Check that opencode is installed
if ! command -v opencode &>/dev/null; then
  echo "ERROR: opencode is not installed. Install it from https://opencode.ai"
  exit 1
fi

# Seed memory.md if it does not exist
if [ ! -f "$PROJECT_DIR/memory.md" ]; then
  cat > "$PROJECT_DIR/memory.md" << 'SEED'
# Project Memory

## Status
- **Project status**: not_started
- **Last run**: never
- **Run count**: 0

## Summary
No work has been done yet.

## Completed Issues
None yet.

## Active Issues
None yet.

## Decisions
None yet.

## Blockers
None yet.

## Next Priorities
None yet.
SEED
  echo "[setup] Created initial memory.md"
fi

# Check that goal.md exists and is not empty
if [ ! -s "$PROJECT_DIR/goal.md" ]; then
  echo "ERROR: goal.md is missing or empty. Please write your project goal first."
  exit 1
fi

# Check that gh CLI is authenticated
if ! gh auth status &>/dev/null; then
  echo "ERROR: gh CLI is not authenticated. Run: gh auth login"
  exit 1
fi

# Check that the repo has a GitHub remote
if ! git remote get-url origin &>/dev/null; then
  echo "ERROR: No git remote 'origin' configured."
  echo "Create a GitHub repo and run: git remote add origin <url>"
  exit 1
fi

# Ensure required labels exist on the repo
ensure_labels() {
  echo "[setup] Ensuring GitHub labels exist..."
  for label in ready in-progress blocked completed; do
    gh label create "$label" --force 2>/dev/null || true
  done
}

# ---------------------------------------------------------------------------
# Core functions
# ---------------------------------------------------------------------------

run_manager() {
  local cycle=$1
  local log_file="$LOG_DIR/${TIMESTAMP}_cycle${cycle}_manager.log"
  echo ""
  echo "--- MANAGER (cycle $cycle) ---"
  echo "[$(date '+%H:%M:%S')] Starting manager agent..."

  opencode run \
    --agent manager \
    --title "manager-cycle-${cycle}-${TIMESTAMP}" \
    "You are the Manager Agent. Execute your full protocol now:
1. Read goal.md and memory.md
2. Query all open GitHub issues with: gh issue list --state open --json number,title,labels,body,comments --limit 50
3. Query recently closed issues with: gh issue list --state closed --json number,title,labels --limit 20 --search 'sort:updated-desc'
4. Analyze the state: count ready/in-progress/blocked issues, identify gaps vs the goal
5. Unblock any blocked issues if possible (highest priority)
6. Create new ready issues for work that has no issue yet (target: 2-3 ready issues)
7. Close any stale or irrelevant issues
8. Update memory.md with your decisions and the current timestamp
9. Print a summary of actions taken" \
    2>&1 | tee "$log_file"

  local exit_code=${PIPESTATUS[0]}
  echo "[$(date '+%H:%M:%S')] Manager finished (exit code: $exit_code)"
  return $exit_code
}

run_swe() {
  local cycle=$1
  local run=$2
  local log_file="$LOG_DIR/${TIMESTAMP}_cycle${cycle}_swe${run}.log"
  echo ""
  echo "--- SWE (cycle $cycle, run $run) ---"
  echo "[$(date '+%H:%M:%S')] Starting SWE agent..."

  opencode run \
    --agent swe \
    --title "swe-cycle-${cycle}-run-${run}-${TIMESTAMP}" \
    "You are the SWE Agent. Execute your full protocol now:
1. Query for ready issues: gh issue list --label ready --state open --json number,title,body --jq 'sort_by(.number)' --limit 10
2. If no ready issues, print 'No ready issues available. Exiting.' and stop
3. Pick the lowest-numbered ready issue, check its dependencies
4. Claim it (change label to in-progress, add a comment)
5. Understand the task from the issue body and codebase exploration
6. Implement the solution
7. Validate (run tests if they exist)
8. Report results: commit and close if done, or mark blocked with explanation" \
    2>&1 | tee "$log_file"

  local exit_code=${PIPESTATUS[0]}
  echo "[$(date '+%H:%M:%S')] SWE finished (exit code: $exit_code)"
  return $exit_code
}

check_all_blocked() {
  # Returns 0 (true in bash) if there are no actionable issues
  local ready_count in_progress_count

  ready_count=$(gh issue list --label "ready" --state open --json number --jq 'length' 2>/dev/null || echo "0")
  in_progress_count=$(gh issue list --label "in-progress" --state open --json number --jq 'length' 2>/dev/null || echo "0")

  if [ "$ready_count" -eq 0 ] && [ "$in_progress_count" -eq 0 ]; then
    return 0  # All blocked or no work
  fi
  return 1    # There is actionable work
}

check_project_completed() {
  # Returns 0 (true) if memory.md says the project is completed
  if [ ! -f "$PROJECT_DIR/memory.md" ]; then
    return 1
  fi

  if grep -q '\*\*Project status\*\*: completed' "$PROJECT_DIR/memory.md" 2>/dev/null; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

echo "============================================================"
echo "  ray-agents orchestrator"
echo "  Project:  $PROJECT_DIR"
echo "  Cycles:   $MAX_CYCLES"
echo "  SWE runs: $SWE_RUNS_PER_CYCLE per cycle"
echo "  Logs:     $LOG_DIR/"
echo "  Started:  $(date)"
echo "============================================================"

ensure_labels

for cycle in $(seq 1 "$MAX_CYCLES"); do
  echo ""
  echo "============ CYCLE $cycle / $MAX_CYCLES ============"

  # --- Phase 1: Manager ---
  if ! run_manager "$cycle"; then
    echo "[WARN] Manager exited with error. Continuing to SWE phase."
  fi

  # Check if project is done
  if check_project_completed; then
    echo ""
    echo "[DONE] Manager marked project as completed. Stopping."
    break
  fi

  # --- Phase 2: SWE agent (up to N runs) ---
  for swe_run in $(seq 1 "$SWE_RUNS_PER_CYCLE"); do

    # Before each SWE run, check if there is actionable work
    if check_all_blocked; then
      echo ""
      echo "[INFO] No ready or in-progress issues. All blocked or done."
      echo "[INFO] Returning to manager early."
      break
    fi

    if ! run_swe "$cycle" "$swe_run"; then
      echo "[WARN] SWE exited with error on run $swe_run. Continuing."
    fi

    # Small delay between SWE runs to let GitHub API settle
    sleep 3
  done

  echo ""
  echo "[INFO] Cycle $cycle complete."

  # Small delay between cycles
  sleep 2
done

echo ""
echo "============================================================"
echo "  Orchestration finished."
echo "  Total cycles: $MAX_CYCLES"
echo "  Logs:     $LOG_DIR/"
echo "  Finished: $(date)"
echo "============================================================"

# Final status
if check_project_completed; then
  echo "  Status: PROJECT COMPLETED"
else
  echo "  Status: Stopped (cycle limit reached or manual interruption)"
  echo "  To continue: ./run.sh --max-cycles $MAX_CYCLES --swe-runs-per-cycle $SWE_RUNS_PER_CYCLE"
fi
