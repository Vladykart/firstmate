#!/usr/bin/env bash
set -eu

ROOT="$PWD"
source <(sed -n '1,3287p' tests/fm-daemon.test.sh | sed "s#\. \"\$(dirname \"\${BASH_SOURCE\[0\]}\")/wake-helpers.sh\"#. \"$PWD/tests/wake-helpers.sh\"#")

state=$(make_supercase live-pause-wedge-evidence)/state
task=live-worker
window=sess:fm-live-worker
reason="stale: $window (idle 250s, possible wedge, escalation 3)"
printf 'window=%s\nkind=ship\nharness=claude\n' "$window" > "$state/$task.meta"

printf 'RUN_STARTED_UTC=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
generation=$("$ROOT/bin/fm-busy-event.sh" arm "$state" "$task")
printf 'BUSY_SNAPSHOT_BEFORE=%s\n' "$(fm_busy_record_read "$state" "$task" snapshot)"

"$ROOT/bin/fm-status-append.sh" "$state" "$task" 'paused: deliberately parked on external review'
printf 'BOUND_PAUSE=%s\n' "$(tail -1 "$state/$task.status")"
if fm_busy_declared_pause_valid "$state" "$task" require-bound; then
  printf 'BOUND_PAUSE_VALID=yes\n'
else
  printf 'BOUND_PAUSE_VALID=no\n'
  exit 1
fi

FM_STATE_OVERRIDE="$state" handle_wake "$reason" "$state" || true
if [ -s "$state/.subsuper-escalations" ]; then
  printf 'BOUND_PAUSE_WATCHER_OUTPUT=%s\n' "$(cat "$state/.subsuper-escalations")"
  exit 1
else
  printf 'BOUND_PAUSE_WATCHER_OUTPUT=<quiet; long-cadence marker present=%s>\n' "$(test -e "$state/.subsuper-paused-live-worker" && echo yes || echo no)"
fi

"$ROOT/bin/fm-busy-event.sh" apply "$state" "$task" idle --gen "$generation" --source claude-hook --event stop
printf 'BUSY_SNAPSHOT_AFTER=%s\n' "$(fm_busy_record_read "$state" "$task" snapshot)"
if fm_busy_declared_pause_valid "$state" "$task" require-bound; then
  printf 'STALE_PAUSE_VALID=yes\n'
  exit 1
else
  printf 'STALE_PAUSE_VALID=no\n'
fi

: > "$state/.subsuper-escalations"
FM_STATE_OVERRIDE="$state" handle_wake "$reason" "$state" || true
printf 'STALE_PAUSE_WATCHER_OUTPUT=%s\n' "$(cat "$state/.subsuper-escalations")"
printf 'RUN_FINISHED_UTC=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
