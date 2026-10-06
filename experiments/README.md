# experiments: standalone Trinity vs Trinity inside ORP

> Development version: experimental scripts for timing this fork of Trinity.

Slurm scripts that run Trinity from this fork on five samples and record
timings, to compare with the Trinity step of the Oyster River Protocol (ORP).

| file | what |
| --- | --- |
| `samples.tsv` | the samples: id, read 1, read 2. Edit to choose others |
| `trinity_standalone.sbatch` | array job, one task per line of `samples.tsv` |
| `submit.sh` | makes the log directory, checks the reads exist, submits |
| `compare_timings.py` | standalone timings next to ORP's, from the logs |

## What is run

**Input.** ORP's own trimmed and rcorrector-corrected reads
(`compare/orp_runs/<id>/rcorr/<id>.TRIM_{1,2}P.cor.fq.gz`), so both sides
assemble identical input. The default five are ERR1674585, SRR1789336,
ERR058009, ERR1016675 and DRR046632: all have finished ORP Trinity runs, and
they span a range of sizes.

**Command.** The same as `oyster.py` runs, in the same two stages, unstranded
with Trinity's default normalization and `--inchworm_cpu 10`:

1. phase 1: `Trinity ... --no_distributed_trinity_exec` (Inchworm, Chrysalis)
2. phase 2: `Trinity ... --full_cleanup` (per-component assemblies, ParaFly)

Each stage is timed separately.

**Resources.** One exclusive 40-core node per sample (`--mem=0`, Trinity
`--max_memory 600G`). ORP gave each phase a share of a node, shared with SPAdes
(phase 1) and Trans-ABySS (phase 2), and ran phase 2 on bioconda's serial
ParaFly. So phase 1 is not like for like. The CPU counts are recorded in the
output so the comparison can say so.

The sbatch refuses to start if the checkout's ParaFly lacks OpenMP.

## Running

On Premise, with the fork built (`make -j 8 no_bamsifter`, see
[INSTALL.md](../INSTALL.md)):

```bash
cd ~/trinityrnaseq_2026/experiments && ./submit.sh
```

Or only some samples (line numbers of `samples.tsv`):

```bash
./submit.sh 2,4
```

Outputs go to `/mnt/home/macmaneslab/macmanes/compare/trinity_standalone/`
(override with `OUTROOT`):

| path | what |
| --- | --- |
| `<id>/<id>.trinity.Trinity.fasta` | the assembly |
| `<id>/timing.tsv` | phase 1, phase 2 and total seconds, exit codes, start and end times |
| `timings.tsv` | one row per run: commit, node, cpu, mem, phase times, transcripts, Slurm job |
| `logs/trin_<jobid>_<task>.log` | the Trinity output |

Each run starts clean (it deletes that sample's previous output), so the times
are for a full run.

## Comparing with ORP

```bash
module load anaconda/colsa && python3 compare_timings.py
```

Reads `timings.tsv` and ORP's `run_trinity_phase1/2 -- done ... (Ns)` log lines,
and writes `comparison.tsv` (hours and speedup, with the CPUs each side used).

## To compare against the stock Trinity as well

Point `TRINITY_SRC` at another build and set a different label, so the rows
are told apart in `timings.tsv`:

```bash
TAG=stock TRINITY_SRC=/path/to/other/trinity ./submit.sh
```
