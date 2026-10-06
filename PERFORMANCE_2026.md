# Trinity phase 2 performance, 2026

This fork of trinityrnaseq/trinityrnaseq (v2.15.2, upstream 653e43a) holds
fixes that take Trinity's phase 2 (the per-component assemblies run through
ParaFly) from 34 h to under 1 h on a 40-core node, plus the reproducibility
fixes needed to show the speed changes leave the assembly unchanged. Found
and measured in October 2026 on UNH's Premise cluster while profiling the
Oyster River Protocol (ORP), where Trinity was the bottleneck.

## Results

SRR1789336, phase 2 only: all 73,737 `recursive_trinity.cmds` from one
phase-1 run, replayed on one exclusive 40-core node (2x Xeon, GPFS), 40
ParaFly slots.

| build | phase 2 wall |
| --- | --- |
| bioconda `trinity=2.15.2` build `_6` (what ORP was running) | 34h27m |
| same install, ParaFly rebuilt with OpenMP | 2h03m |
| upstream + this fork's reproducibility fixes (baseline for the speed changes) | 2h06m |
| this fork | **58m** |

The last two give byte-identical `*.out.Trinity.fasta` for all 66,440
components that assemble anything (the other 7,297 produce nothing in
either); none failed.

## 1. Bioconda's ParaFly runs serially

Bioconda builds `_4`, `_5` and `_6` of `trinity=2.15.2` (May 2025 on) ship a
ParaFly compiled without OpenMP. It links libgomp but has no `GOMP_` loop
symbols, so `ParaFly -CPU 40` runs its commands one at a time and phase 2
uses one core whatever `--CPU` says. Builds `_0` to `_3` are fine.

    nm -D $CONDA_PREFIX/bin/trinity-plugins/BIN/ParaFly | grep -c GOMP_    # 0 = serial

Causes (`perf2026/harness/pf_fix_test.sh` reproduces them):

- bioconda's `makefile.patch` replaces ParaFly's `CFLAGS="-fopenmp"
  CXXFLAGS="-fopenmp"` with the recipe's flags. Those included `${LDFLAGS}`,
  which holds `-fopenmp`, until the 2025-05-29 rebuild (bioconda-recipes
  #56483).
- ParaFly's `configure.ac` would have caught it, but `AC_OPENMP` compiles its
  probe with `LDFLAGS`, so `-fopenmp` there reads as "none needed" while the
  real compiles never see `LDFLAGS`: the `#pragma omp parallel for` is
  dropped and libgomp is still linked.
- `AC_SUBST([AM_CXXFLAGS], [-m64 $OPENMP_CXXFLAGS])` is unquoted. When
  `AC_OPENMP` does find `-fopenmp`, configure runs it as a command
  (`configure: line 3103: -fopenmp: command not found`) and loses it, which
  is presumably why `trinity-plugins/Makefile` passes `CXXFLAGS="-fopenmp"`.

Fixed here in `trinity-plugins/ParaFly/configure.ac` (configure regenerated
with automake 1.16; the change itself is 8 lines). With it, a plain
`configure`, bioconda's flags and Trinity's Makefile flags all give an
OpenMP ParaFly (before: no, no, yes).

Bioconda recipe fix, independent of this fork: in
`recipes/trinity/makefile.patch`, give ParaFly
`CFLAGS="${CFLAGS} -fopenmp" CXXFLAGS="${CXXFLAGS} -fopenmp"`, bump the
build number, and add a test that fails on a serial ParaFly, e.g.

    printf 'sleep 2\nsleep 2\n' > cmds
    s=$(date +%s); ParaFly -c cmds -CPU 2; test $(( $(date +%s) - s )) -lt 4

## 2. What a phase-2 component costs

With a working ParaFly, a 1,500-component sample (seed 1; 2.0% of jobs, 2.3%
of read bytes): median component 3.4 s wall, median input 1.7 KB (about 7
reads), 99% of components under 15 s. Almost all the time is fixed cost per
mini-Trinity run:

| stage | CPU share | cause |
| --- | --- | --- |
| Butterfly | 42% | JVM C2 JIT threads, ~1.7 CPU-s per call on a 40-core node; debug messages built and discarded |
| GraphFromFasta | 10% | allocates, zeroes, sorts and frees a dense 4^12-slot k-mer table (~450 MB) per component |
| bowtie2-build, bowtie2 + samtools | 12% | python and perl wrappers; run even with fewer than 2 contigs to scaffold (74% of components) |
| SuperTranscripts polish | 7% | `import numpy` (~0.1 s) for one `argmax` and one `zeros` |
| shell-outs, tool probes, Perl startup | ~12% | `sh -c command -v` x5, `samtools --version`, `jellyfish --version`, `sort --help`, `touch` and `mkdir -p` through bash, every component |

Butterfly under JFR: 60-75% of samples in `SeqVertex.getWeightAvg()` via
`toString()`, from `debugMes(...)` arguments that `debugMes` then drops
(`DEBUG` is a compile-time `true` and the level test is inside the call;
775 call sites). The five largest components of the run (4.9-6.7 MB of
reads) take 20-27 s each, so there is no long tail.

## 3. Reproducibility

- **SuperTranscripts polish.** `Compact_graph_pruner.pop_small_bubbles` keeps
  `bubble_node_list.pop()` from a list built off a `set` of `TNode`s, which
  hash by `id()`, so the base kept at a SNP-sized bubble depends on memory
  layout. The same `Trinity.tmp.fasta` gave four different outputs
  depending only on the input and output path strings, so the same data run
  in two directories assembles differently (1.2% of components here).
- **Butterfly.** Eight classes used as HashMap/HashSet keys (jung keys its
  edge maps by `SimpleEdge`) have no `hashCode`, so order follows the JVM
  identity hash. For ~0.15% of components the output flips between two
  alternatives with the identity hash sequence, which moves with
  `-XX:hashCode`, the locale (it changes how many identity hashes the JVM
  uses at startup), JDK version, and any change to which code runs.
- **Butterfly source.** The `Butterfly/Butterfly` submodule pointed at the
  2019 `master` ("init"), but the shipped `Butterfly.jar` (classes dated
  2022-03-10) is `devel` (d3cb730); building the submodule as pinned gives a
  different Butterfly.
- `scaffold_iworm_contigs.pl` breaks count ties in Perl's randomized hash
  order (no downstream effect seen).
- Not an issue: locale for `sort`. `COMMON.pm` sets `LC_ALL=C` for the run.

## Changes in this fork

| where | change | effect | validation |
| --- | --- | --- | --- |
| Trinity | det-fix: bubble representative is the node in most isoforms, ties by loc id; scaffold tie-break | path-independent output | same output at 8 paths; two runs at different paths agree on 1346/1346 |
| Trinity | Butterfly runs C1-only (`-XX:TieredStopAtLevel=1`); `--bfly_full_jit` restores the default | Butterfly CPU -58%; largest components: wall within +/-15%, CPU 2.3-3.3x lower | identical |
| Trinity | SuperTranscripts polish without numpy | -0.1 s per component | identical |
| Trinity | fewer processes per component: PATH lookups in Perl, no tool version probes in `--trinity_complete` runs (the parent checked), one `sort --parallel` probe per run tree, Perl touch/mkdir/checkpoints, `bowtie2-build-s`/`bowtie2-align-s` called directly, read-pair scaffolding skipped with fewer than 2 contigs | | identical |
| ParaFly | configure.ac fixes above | OpenMP whatever the build flags | 6 GOMP symbols under all three flag sets |
| Chrysalis (`chrysalis-2026`) | sparse k-mer table below bound/16 k-mer positions; dense above (phase 1) | GraphFromFasta 0.20 s -> 0.02 s, 464 MB -> 6 MB on a small component | dense, sparse and auto identical; `CHRYSALIS_KMER_TABLE=dense\|sparse` forces either |
| Butterfly (`butterfly-2026`, on upstream `devel`) | reproducible hash codes: creation counter through MurmurHash3 fmix32 | output no longer depends on the identity hash | one output per component across 2 locales x 4 `-XX:hashCode` modes x debug-message change on/off; vs the shipped jar 1344/1346 identical, +0.09% transcripts |
| Butterfly | debug messages built only when printed | Butterfly 2.4 -> 0.6 s, 2.3 -> 0.8 s, 0.55 -> 0.31 s on three components | identical given the previous change |
| `Butterfly.jar` | rebuilt from `butterfly-2026` (javac `--release 8`, classes over the previous fat jar's bundled dependencies) | | `devel` built unmodified reproduces the old jar |

The Chrysalis and Butterfly changes live on branches of this repository, and
`.gitmodules` points there, so `git clone --recursive` gets them.

Sample, 1,500 components, 38 slots:

| | ParaFly wall | component CPU | median component | Butterfly CPU |
| --- | --- | --- | --- | --- |
| reproducibility fixes only | 157 s | 4,036 s | 3.4 s | 1,659 s |
| this fork | 75 s | 1,527 s | 1.4 s | 449 s |

## Using it

Build:

    git clone --recursive https://github.com/macmanes-lab/trinityrnaseq_2026.git
    cd trinityrnaseq_2026 && make && make plugins

(bamsifter, used only by genome-guided mode, needs autoheader to build.)
Check `nm -D trinity-plugins/BIN/ParaFly | grep -c GOMP_` is non-zero.

Or patch an existing bioconda install in place, with a backup:

    SRC=$PWD perf2026/install_into_env.sh parafly $CONDA_PREFIX/bin   # ParaFly only
    SRC=$PWD perf2026/install_into_env.sh full    $CONDA_PREFIX/bin   # everything
    perf2026/install_into_env.sh restore $CONDA_PREFIX/bin

## Reproducing the measurements

`perf2026/harness/` (paths in the scripts are Premise's):

- `replay.py` copies a seeded sample of real phase-2 commands (or all) from a
  phase-1 output into a sandbox, runs them with a given Trinity, and
  compares each component's output with a reference; `replay.sbatch` and
  `full_replay.sbatch` drive it under Slurm.
- `perf2026/patches/0001-prof-*.patch` with `TrinProf.pm` adds an opt-in
  per-command timing log (`TRINITY_PROF_LOG`); `javashim`, `pyshim` time each
  java and python call; `analyze.py` summarizes a run.
- `build_bfly.sh` builds `Butterfly.jar` from source; `guard_debug.py` is the
  mechanical rewrite behind the debug-message change.
- `pf_fix_test.sh` reproduces the ParaFly configure bugs and the fix.
- `isolate.sh`, `envtest2.sh`, `bisect_guard.sh`, `heavy_jit.sh` are the
  Butterfly determinism and JIT experiments.
