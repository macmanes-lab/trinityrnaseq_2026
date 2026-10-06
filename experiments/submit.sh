#!/bin/bash
# Submit one array task per line of samples.tsv.
#   ./submit.sh                 # all samples
#   ./submit.sh 2,4             # only lines 2 and 4 of samples.tsv
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUTROOT="${OUTROOT:-/mnt/home/macmaneslab/macmanes/compare/trinity_standalone}"
N=$(grep -v '^#' "$HERE/samples.tsv" | grep -c .)
RANGE="${1:-1-$N}"
mkdir -p "$OUTROOT/logs"
# fail now, not 5 jobs later, if a read file is missing
grep -v '^#' "$HERE/samples.tsv" | grep . | while IFS=$'\t' read -r id r1 r2; do
    for f in "$r1" "$r2"; do [ -f "$f" ] || { echo "missing: $f" >&2; exit 1; }; done
done
sbatch --array="$RANGE" --export=ALL,TRINITY_SRC="$(cd "$HERE/.." && pwd)" "$HERE/trinity_standalone.sbatch"
