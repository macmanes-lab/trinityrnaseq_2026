# Fork vs stock Trinity, same node: SRR1138704 (2026-10-13)

> Development version: an experiment record for this fork of Trinity.

**Result.** On the same node, with the same reads and the same commands, this
fork ran Trinity phase 2 **2.2x faster** than stock Trinity v2.15.2
(32m53s vs 1h11m05s). Phase 1 was the same speed for both. The whole Trinity
step went from 1h41m46s to 1h03m40s (**1.6x**, 38 minutes saved). The two
assemblies are equivalent.

This is the first like-for-like comparison against stock Trinity with a
working (OpenMP) ParaFly. The 2026-10-06 standalone runs
([HANDOFF.md](../../HANDOFF.md) section 8) compared the fork with ORP runs that
used bioconda's serial ParaFly, and with different core counts. That left
"run stock Trinity as a third arm" as an open item. This run covers it for
one sample.

## Setup

| | |
| --- | --- |
| Slurm job | 1322066, Premise `shared` partition, node181 (not exclusive) |
| resources | 40 cores, 120G; Trinity `--max_memory 108G` |
| input | ORP's trimmed and rcorrector-corrected reads for SRR1138704 (run `SRR1138704_dev24`, `rcorr/*.TRIM_{1,2}P.cor.fq.gz`), unpacked to `.fq` on fast scratch before timing, as the ORP run read them |
| fork | `~/trinityrnaseq_2026`, `4599e21` (`master`; code identical to `648ea44`) |
| stock | ORP's `orp_trinity` Trinity: upstream `Trinity-v2.15.2` (`633f3cb`) built from source, ParaFly with OpenMP (6 `GOMP_` symbols) |
| order | fork (phase 1, phase 2), then stock (phase 1, phase 2), one after the other in the same job |
| output | `/mnt/gpfs01/fast/macmaneslab` scratch, one directory per build |

Both builds ran through `conda run -n orp_trinity`, so they used the same
jellyfish, bowtie2, salmon, perl and java (openjdk 25). Each ran the two
stages ORP's `oyster.py` runs, with ORP's options: unstranded, Trinity's
default normalization, `--inchworm_cpu 10`. Only `--CPU` and `--max_memory`
differ from the ORP run (`SRR1138704_dev24`, ORP 4.1.0-dev24), which gave
Trinity a share of a node:

```bash
# phase 1 (Inchworm, Chrysalis)
conda run --no-capture-output -n orp_trinity <Trinity> --no_version_check --bypass_java_version_check \
    --seqType fq --output <dir>/SRR1138704_dev24.trinity --max_memory 108G \
    --left <R1.cor.fq> --right <R2.cor.fq> --CPU 40 --inchworm_cpu 10 --no_distributed_trinity_exec
# phase 2 (per-component assemblies under ParaFly)
conda run --no-capture-output -n orp_trinity <Trinity> ...same... --full_cleanup
```

After phase 1, each build's `recursive_trinity.cmds` was checked to call that
build's own `Trinity` for the components.

Script: [`../fork_vs_stock.sbatch`](../fork_vs_stock.sbatch). Raw timings:
[`fork_vs_stock_SRR1138704_timing.tsv`](fork_vs_stock_SRR1138704_timing.tsv).

## Timings

| build | phase 1 | phase 2 | total | components |
| --- | --- | --- | --- | --- |
| fork | 30m47s (1,847 s) | **32m53s** (1,973 s) | **1h03m40s** (3,820 s) | 58,499 |
| stock | 30m41s (1,841 s) | 1h11m05s (4,265 s) | 1h41m46s (6,106 s) | 58,492 |
| fork / stock | 1.00 | **0.46 (2.16x faster)** | **0.63 (1.60x faster)** | |

- **Phase 2: 2.16x faster.** This agrees with the full SRR1789336 replay on an
  exclusive node in [PERFORMANCE_2026.md](../../PERFORMANCE_2026.md) (2h06m
  vs 58m, 2.17x). The gain holds on a second dataset, end to end, run the
  way ORP launches Trinity.
- **Phase 1: no change** (6 s apart). The fork leaves Inchworm alone, and
  its Chrysalis change (the sparse k-mer table) was aimed at the many small
  per-component runs in phase 2. Phase 1 is now about half of the fork's
  Trinity time, so it is where the next gain is (see `inchworm-2026`).

## Assemblies

| build | transcripts | genes | bases | N50 |
| --- | --- | --- | --- | --- |
| fork | 90,183 | 66,643 | 50,081,397 | 696 |
| stock | 90,194 | 66,626 | 50,173,516 | 698 |
| fork - stock | -11 (-0.01%) | +17 (+0.03%) | -92,119 (-0.18%) | -2 |

These are equivalent. The two can't be byte-identical: stock Trinity's
output depends on the run directory and the JVM identity hash, and the fork
fixes both ([PERFORMANCE_2026.md](../../PERFORMANCE_2026.md) section 3). The
fork's own output was shown byte-identical to the reproducible baseline in
the SRR1789336 replay. No BUSCO or other quality metrics were run on these
two assemblies.

## For comparison: the same data inside ORP

The ORP run that made these reads (`SRR1138704_dev24`, Slurm job 1321504,
node139, `--cpu 40 --mem 500 --normalize-reads`, stock Trinity) gave Trinity
fewer cores and ran it alongside other assemblers:

| | phase 1 | phase 2 | Trinity total |
| --- | --- | --- | --- |
| ORP dev24 | 41m09s on 21 cores (beside SPAdes) | 1h41m17s on 31 cores (beside Trans-ABySS) | 2h22m26s |

An earlier stock run on the same reads (ORP repo, job 1321673, node139, 40
cores, 250G) took 38m22s for phase 1 and 1h38m04s for ParaFly in phase 2. Phase
2 in this run (stock, 1h11m05s) was faster, so node-to-node variation on
Premise is large. That is why both builds were run on one node here.

**What the gain might be inside ORP (an estimate, not measured).** In
dev24, Trinity's phases (2h22m in total) ran beside Trans-ABySS (1h53m).
If phase 2 halves inside ORP as well, Trinity finishes before Trans-ABySS
on this dataset, so ORP's total would drop by about 30 minutes rather than
the full phase 2 saving. Datasets where Trinity sets ORP's total time (for
example SRR1139191 and SRR868662, with phase 2 at about 5 hours in dev24)
should gain more. To measure it, run a full ORP job with the fork installed
into `orp_trinity` (`perf2026/install_into_env.sh`; `restore` undoes it).

## Caveats

- One sample, one node, one run per build. The node was shared (not
  exclusive), so another job could have slowed either build.
- The fork ran first. The reads were already unpacked before either build
  started, and if file caching favoured anyone, it favoured stock, which
  ran second.
- The stock checkout shows `-dirty` because its ParaFly was rebuilt in place
  with OpenMP. Its Trinity, Inchworm, Chrysalis and Butterfly are upstream
  v2.15.2.

## Reproduce

On Premise, with the fork built at `~/trinityrnaseq_2026`:

```bash
mkdir -p ~/trinity_fork_test && cd ~/trinity_fork_test
sbatch ~/trinityrnaseq_2026/experiments/fork_vs_stock.sbatch
```

The script's input paths (the `SRR1138704_dev24` ORP run) are hard-coded at
the top. `ARMS="fork"` or `ARMS="stock"` runs just one build. Results go
to `~/trinity_fork_test/<jobid>/`: `summary.txt`, `timing.tsv`, both
assemblies, and a log for each build and phase. The scratch directory is
deleted at the end.
