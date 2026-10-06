#!/bin/bash
# Put this fork's phase-2 fixes into an installed Trinity (e.g. a bioconda
# env), keeping a backup.
#
#   SRC=/path/to/built/trinityrnaseq_2026 install_into_env.sh parafly TRINITY_HOME
#       ParaFly with OpenMP only: the assembly is unchanged
#   SRC=... install_into_env.sh full TRINITY_HOME
#       plus the Trinity, Chrysalis and Butterfly changes
#   install_into_env.sh restore TRINITY_HOME
#
# TRINITY_HOME is the directory holding the Trinity script; for bioconda that
# is $CONDA_PREFIX/bin. SRC is a checkout of this repository after
# `git submodule update --init --recursive` and `make`. The Trinity-side
# changes are applied as a patch (git diff from upstream 653e43a), so local
# edits a package made to those files, such as bioconda's trimmomatic paths in
# the Trinity script, are kept.
set -euo pipefail

UPSTREAM=653e43a777390bb5cde27d6f27673dadfe1c7115

# replace by rename, so a binary that a running job has open keeps its old
# inode instead of being overwritten under it
put() { cp "$1" "$2.new.$$" && chmod --reference="$2" "$2.new.$$" && mv -f "$2.new.$$" "$2"; }

MODE=${1:?usage: $0 parafly|full|restore TRINITY_HOME}
TH=$(cd "${2:?usage: $0 parafly|full|restore TRINITY_HOME}" && pwd)
BACKUP=$TH/../trinity_phase2_backup.tar

[ -f "$TH/Trinity" ] || { echo "no Trinity script in $TH" >&2; exit 1; }

FILES=(
    Trinity
    PerlLib/COMMON.pm
    PerlLib/Pipeliner.pm
    util/support_scripts/scaffold_iworm_contigs.pl
    Analysis/SuperTranscripts
    Chrysalis/bin
    Butterfly/Butterfly.jar
    trinity-plugins/BIN/ParaFly
)

if [ "$MODE" = restore ]; then
    [ -f "$BACKUP" ] || { echo "no backup at $BACKUP" >&2; exit 1; }
    tar -xf "$BACKUP" -C "$TH"
    rm "$BACKUP"
    echo "restored $TH from $BACKUP"
    exit 0
fi

SRC=${SRC:?set SRC to a built checkout of trinityrnaseq_2026}
case $MODE in parafly|full) ;; *) echo "unknown mode $MODE" >&2; exit 1 ;; esac

if [ -f "$BACKUP" ]; then
    echo "$BACKUP exists: already installed? run '$0 restore $TH' first" >&2
    exit 1
fi

parafly=$SRC/trinity-plugins/BIN/ParaFly
nm -D "$parafly" | grep -q GOMP_ || { echo "$parafly was built without OpenMP" >&2; exit 1; }

(cd "$TH" && tar -cf "$BACKUP" "${FILES[@]}")
echo "backed up originals to $BACKUP"

put "$parafly" "$TH/trinity-plugins/BIN/ParaFly"
echo "ParaFly: OpenMP build installed"

if [ "$MODE" = full ]; then
    git -C "$SRC" diff "$UPSTREAM" HEAD -- Trinity PerlLib util Analysis \
        | patch -d "$TH" -p1 --forward --no-backup-if-mismatch -s
    echo "Trinity, PerlLib, util, Analysis: patched"
    for b in "$SRC"/Chrysalis/bin/*; do put "$b" "$TH/Chrysalis/bin/$(basename "$b")"; done
    echo "Chrysalis: sparse k-mer table build installed"
    put "$SRC/Butterfly/Butterfly.jar" "$TH/Butterfly/Butterfly.jar"
    echo "Butterfly: jar installed"
    perl -I"$TH/PerlLib" -c "$TH/Trinity"
fi
