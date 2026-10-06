#!/bin/bash
#SBATCH --partition=macmanes,shared
#SBATCH -J trin_sa
#SBATCH --cpus-per-task=40
#SBATCH --mem=700G
#SBATCH --array=1-5
#SBATCH --output=/mnt/home/macmaneslab/macmanes/compare/trinity_standalone/logs/trin_%A_%a.log
#
# Standalone (non-ORP) Trinity from this fork, one array task per line of
# samples.tsv. Submit with ./submit.sh, which creates the log directory first
# (slurm opens --output before this script runs).
#
# To make the timings comparable with Trinity inside ORP, this runs the same
# two stages ORP does (see run_trinity_phase1/2 in oyster.py) on the same
# input (ORP's trimmed + rcorrector-corrected reads) with the same options,
# and times each stage separately:
#   phase 1  Trinity ... --no_distributed_trinity_exec   (Inchworm + Chrysalis)
#   phase 2  Trinity ... --full_cleanup                  (per-component, ParaFly)
# The difference is resources: ORP gives phase 1 a share of the node, shared
# with SPAdes, and phase 2 a share shared with Trans-ABySS. Here each phase
# gets 40 cores (the node may be shared with other jobs), so compare phase 2 mainly, and note CPU counts
# (recorded in the timing file).
#
# Environment overrides: TRINITY_SRC, TOOLS_ENV, OUTROOT, MEM, CPU, SAMPLES, TAG.

set -uo pipefail

TRINITY_SRC="${TRINITY_SRC:-$HOME/trinityrnaseq_2026}"
TOOLS_ENV="${TOOLS_ENV:-$HOME/orp_envs/orp_trinity}"       # jellyfish, bowtie2, samtools, salmon, java
OUTROOT="${OUTROOT:-/mnt/home/macmaneslab/macmanes/compare/trinity_standalone}"
SAMPLES="${SAMPLES:-$TRINITY_SRC/experiments/samples.tsv}"
TAG="${TAG:-fork}"                                         # label for the timing table
CPU="${CPU:-${SLURM_CPUS_PER_TASK:-40}}"
MEM="${MEM:-600}"                                          # GB, for --max_memory
INCHWORM_CPU=10                                            # same as ORP

TASK="${SLURM_ARRAY_TASK_ID:-1}"
echo "=== task $TASK of ${SLURM_ARRAY_JOB_ID:-local} on $(hostname) at $(date) ==="

line=$(grep -v '^#' "$SAMPLES" | grep . | sed -n "${TASK}p")
[ -n "$line" ] || { echo "samples.tsv has no line $TASK" >&2; exit 1; }
IFS=$'\t' read -r ID R1 R2 <<< "$line"
for f in "$R1" "$R2"; do [ -f "$f" ] || { echo "missing read file: $f" >&2; exit 1; }; done

# Tools Trinity needs on PATH. Appended, so nothing in the env shadows the
# checkout's own Trinity, ParaFly, Inchworm and Chrysalis.
export PATH="$PATH:$TOOLS_ENV/bin"

TRINITY="$TRINITY_SRC/Trinity"
[ -x "$TRINITY" ] || { echo "no Trinity at $TRINITY (build it: make -j 8 no_bamsifter)" >&2; exit 1; }

# A serial ParaFly makes phase 2 run one component at a time, whatever --CPU says.
gomp=$(nm -D "$TRINITY_SRC/trinity-plugins/BIN/ParaFly" 2>/dev/null | grep -c GOMP_)
if [ "$gomp" -eq 0 ]; then
    echo "ParaFly in $TRINITY_SRC has no OpenMP (GOMP_ count 0): phase 2 would be serial. Rebuild." >&2
    exit 1
fi

RUN="$OUTROOT/$ID"
OUT="$RUN/$ID.trinity"        # Trinity requires "trinity" in the output directory name
TIMING="$RUN/timing.tsv"
ALL="$OUTROOT/timings.tsv"
rm -rf "$OUT" "$OUT.Trinity.fasta" "$OUT.Trinity.fasta.gene_trans_map" "$TIMING"   # clean start: timings must be of a full run
mkdir -p "$RUN"
cd "$RUN" || exit 1

commit=$(git -C "$TRINITY_SRC" rev-parse --short HEAD 2>/dev/null || echo unknown)
echo "sample $ID | trinity $commit | cpu $CPU | mem ${MEM}G | ParaFly GOMP_ $gomp"
echo "R1 $R1"; echo "R2 $R2"

# Same options as oyster.py's _trinity_base_cmd (unstranded, normalization on)
base=("$TRINITY" --no_version_check --bypass_java_version_check
      --seqType fq --output "$OUT" --max_memory "${MEM}G"
      --left "$R1" --right "$R2" --CPU "$CPU" --inchworm_cpu "$INCHWORM_CPU")

stage() {   # stage NAME CMD... : run, time, record
    local name=$1; shift
    local t0 t1 rc
    echo "=== $name -- start $(date '+%F %T') ==="
    t0=$(date +%s)
    "$@"; rc=$?
    t1=$(date +%s)
    echo "=== $name -- done $(date '+%F %T') ($((t1-t0))s, exit $rc) ==="
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ID" "$name" "$((t1-t0))" "$rc" "$(date -d @$t0 '+%F %T')" "$(date -d @$t1 '+%F %T')" >> "$TIMING"
    return $rc
}

p1_rc=0; p2_rc=0
stage phase1 "${base[@]}" --no_distributed_trinity_exec || p1_rc=$?
if [ "$p1_rc" -eq 0 ]; then
    stage phase2 "${base[@]}" --full_cleanup || p2_rc=$?
else
    echo "phase 1 failed (exit $p1_rc); skipping phase 2" >&2
fi

total=$(awk -F'\t' '{s+=$3} END {print s+0}' "$TIMING")
printf '%s\ttotal\t%s\t%s\t\t\n' "$ID" "$total" "$((p1_rc+p2_rc))" >> "$TIMING"

# One row per run in the shared table (flock: array tasks finish concurrently)
p1=$(awk -F'\t' '$2=="phase1"{print $3}' "$TIMING"); p2=$(awk -F'\t' '$2=="phase2"{print $3}' "$TIMING")
n=$(grep -c '^>' "$OUT.Trinity.fasta" 2>/dev/null || echo 0)
(
  flock 9
  [ -s "$ALL" ] || printf 'id\ttag\tcommit\tnode\tcpu\tmem_gb\tphase1_s\tphase2_s\ttotal_s\texit\tn_transcripts\tslurm_job\tdate\n' > "$ALL"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ID" "$TAG" "$commit" "$(hostname)" "$CPU" "$MEM" \
      "${p1:-NA}" "${p2:-NA}" "$total" "$((p1_rc+p2_rc))" "$n" "${SLURM_ARRAY_JOB_ID:-0}_${TASK}" "$(date +%F)" >> "$ALL"
) 9>>"$ALL.lock"

echo "=== $ID finished: phase1 ${p1:-NA}s, phase2 ${p2:-NA}s, total ${total}s, $n transcripts, exit $((p1_rc+p2_rc)) ==="
exit $((p1_rc+p2_rc))
