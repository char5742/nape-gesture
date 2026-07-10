#!/bin/bash

# /bin/bash の同一 path のまま exec を繰り返し、pidversion の回帰を検証する。

set -u

ready_path=$1
trigger_path=$2
exec_count=${NAPE_SAMPLE_CPU_SELF_EXEC_COUNT:-0}

if [ "$exec_count" -eq 0 ]; then
  : > "$ready_path"
  while [ ! -f "$trigger_path" ]; do
    /bin/sleep 0.01
  done
fi

if [ "$exec_count" -ge 50 ]; then
  /bin/sleep 5
  exit 0
fi

export NAPE_SAMPLE_CPU_SELF_EXEC_COUNT=$((exec_count + 1))
/bin/sleep 0.02
exec /bin/bash "$0" "$ready_path" "$trigger_path"
