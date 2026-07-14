#!/usr/bin/env bash
# example.sh — <one-line description of what this helper does>
#
# Usage: example.sh <arg1> <arg2>
#
# Bundled with the skill so the agent runs tested logic instead of
# reconstructing it inline. Pair its output with references/topic-1-guide.md.

set -euo pipefail

arg1="${1:-}"
arg2="${2:-}"

if [[ -z "$arg1" ]]; then
  echo "usage: example.sh <arg1> <arg2>" >&2
  exit 1
fi

# --- do the work here ---
echo "Running with arg1=$arg1 arg2=$arg2"
