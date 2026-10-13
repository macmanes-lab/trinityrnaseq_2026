#!/bin/bash
#SBATCH --partition=macmanes,shared
#SBATCH -J trin_fork
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=40
#SBATCH --mem 120G
#SBATCH --exclude=node117,node118
#SBATCH --output=/mnt/home/macmaneslab/macmanes/trinity_fork_test/trin_fork_%j.log
# Trinity from the trinityrnaseq_2026 fork against stock Trinity (ORP's
# orp_trinity, which is what dev24 ran), on SRR1138704_dev24's corrected
# reads, one after the other on this node. Same commands as dev24's
# run_trinity_phase1 / run_trinity_phase2 (oyster.py _trinity_base_cmd:
# unstranded, normalization on, --inchworm_cpu 10); only --CPU and
# --max_memory differ (all 40 cores here, 90% of the job's memory).

set -uo pipefail
NAME=SRR1138704_dev24
SRC=/mnt/home/macmaneslab/macmanes/$NAME/rcorr
FORK=/mnt/home/macmaneslab/macmanes/trinityrnaseq_2026
ARMS="${ARMS:-fork stock}"
RES=/mnt/home/macmaneslab/macmanes/trinity_fork_test/${SLURM_JOB_ID}
SCR=/mnt/gpfs01/fast/macmaneslab/macmanes/scratch/trin_fork_${SLURM_JOB_ID}
CPU=${SLURM_CPUS_PER_TASK:-40}
MAXMEM=$(( ${SLURM_MEM_PER_NODE:-122880} / 1024 * 9 / 10 ))

mkdir -p "$RES" "$SCR"
SCR=$(cd "$SCR" && pwd -P)
TIMING="$RES/timing.tsv"
log() { echo "[$(date '+%F %T')] $*"; }
hms() { printf '%dh%02dm%02ds' $(($1 / 3600)) $(($1 % 3600 / 60)) $(($1 % 60)); }

module load anaconda/colsa
log "=== Trinity fork vs stock: $NAME on $(hostname), $CPU cpus, --max_memory ${MAXMEM}G, arms: $ARMS ==="

STOCK=$(readlink -f "$(conda run --no-capture-output -n orp_trinity which Trinity | grep -m1 /)")
for t in "$FORK/Trinity" "$STOCK"; do
    d=$(dirname "$t")
    g=$(nm -D "$d/trinity-plugins/BIN/ParaFly" 2>/dev/null | grep -c GOMP_)
    log "$t: $(git -C "$d" describe --always --dirty 2>/dev/null), ParaFly GOMP_ symbols $g"
    [ "$g" -gt 0 ] || { echo "serial ParaFly in $d: timings would be wrong" >&2; exit 1; }
done

# dev24 assembled from the uncompressed .cor.fq; cleanup gzipped them since.
t0=$(date +%s)
mkdir -p "$SCR/reads"
for i in 1 2; do zcat "$SRC/$NAME.TRIM_${i}P.cor.fq.gz" > "$SCR/reads/$NAME.TRIM_${i}P.cor.fq" & done
wait
R1="$SCR/reads/$NAME.TRIM_1P.cor.fq"; R2="$SCR/reads/$NAME.TRIM_2P.cor.fq"
log "reads unpacked in $(hms $(( $(date +%s) - t0 ))): $(du -sh "$SCR/reads" | cut -f1)"

printf 'arm\tstage\tseconds\texit\tstart\tend\n' > "$TIMING"
for arm in $ARMS; do
    case $arm in fork) T="$FORK/Trinity" ;; stock) T=Trinity ;; *) echo "arm $arm?" >&2; exit 1 ;; esac
    OUT="$SCR/$arm/$NAME.trinity"
    mkdir -p "$SCR/$arm"
    cd "$SCR/$arm" || exit 1
    base=(conda run --no-capture-output -n orp_trinity "$T" --no_version_check --bypass_java_version_check
          --seqType fq --output "$OUT" --max_memory "${MAXMEM}G"
          --left "$R1" --right "$R2" --CPU "$CPU" --inchworm_cpu 10)
    for st in phase1 phase2; do
        if [ $st = phase1 ]; then cmd=("${base[@]}" --no_distributed_trinity_exec); else cmd=("${base[@]}" --full_cleanup); fi
        log "$arm $st: ${cmd[*]}"
        s=$(date +%s); s_str=$(date '+%F %T')
        "${cmd[@]}" > "$RES/$arm.$st.log" 2>&1; rc=$?
        e=$(date +%s)
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$arm" "$st" $((e - s)) $rc "$s_str" "$(date '+%F %T')" >> "$TIMING"
        log "$arm $st: exit $rc after $(hms $((e - s)))"
        if [ $st = phase1 ]; then
            # the per-component commands must run this arm's Trinity
            log "$arm recursive_trinity.cmds: $(wc -l < "$OUT/recursive_trinity.cmds") commands; first: $(head -1 "$OUT/recursive_trinity.cmds" | cut -c1-200)"
        fi
        [ $rc = 0 ] || break
    done
    if [ -s "$OUT.Trinity.fasta" ]; then
        cp "$OUT.Trinity.fasta" "$RES/$arm.Trinity.fasta"
        cp "$OUT.Trinity.fasta.gene_trans_map" "$RES/$arm.Trinity.fasta.gene_trans_map" 2>/dev/null
    fi
done

fasta_stats() {     # transcripts genes bases N50
    [ -s "$1" ] || { echo "- - - -"; return; }
    awk '/^>/ {if (l) L[n] = l; n++; l = 0; g = $1; sub(/^>/, "", g); sub(/_i[0-9]+$/, "", g); G[g] = 1; next}
         {l += length($0); b += length($0)}
         END {L[n] = l; m = asort(L); h = 0; for (i = m; i >= 1; i--) {h += L[i]; if (h >= b / 2) {nn = L[i]; break}}
              printf "%d %d %d %d\n", n, length(G), b, nn}' "$1"
}

{
echo "=================== Trinity fork vs stock: $NAME ($(hostname), $CPU cpus, ${MAXMEM}G) ==================="
printf '%-6s %10s %10s %10s %11s %8s %12s %6s\n' arm phase1 phase2 total transcripts genes bases N50
for arm in $ARMS; do
    p1=$(awk -F'\t' -v a=$arm '$1 == a && $2 == "phase1" {print $3}' "$TIMING")
    p2=$(awk -F'\t' -v a=$arm '$1 == a && $2 == "phase2" {print $3}' "$TIMING")
    read -r tx gn bp n50 <<< "$(fasta_stats "$RES/$arm.Trinity.fasta")"
    printf '%-6s %10s %10s %10s %11s %8s %12s %6s\n' $arm "$(hms ${p1:-0})" "$(hms ${p2:-0})" "$(hms $(( ${p1:-0} + ${p2:-0} )))" $tx $gn $bp $n50
done
echo "dev24 (1321504, node139): phase1 0h41m09s on 21 cpus (beside SPAdes), phase2 1h41m17s on 31 cpus (beside Trans-ABySS)"
} | tee "$RES/summary.txt"

rm -rf "$SCR"
log "done; results in $RES"
