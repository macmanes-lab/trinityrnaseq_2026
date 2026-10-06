# Handoff: Trinity phase-2 performance work (2026)

Start here when you pick this up, on any machine. Read this file, then
[PERFORMANCE_2026.md](PERFORMANCE_2026.md) for the findings and evidence, and
[INSTALL.md](INSTALL.md) to build or deploy.

Last updated 2026-10-06 (standalone-vs-ORP timings added).

---

## 1. Summary

Trinity was the slowest step in the Oyster River Protocol (ORP), and most of
that time was in phase 2 (Butterfly and the other per-component assemblies
run through ParaFly). Two causes:

1. **A packaging bug, not a code bug.** Bioconda `trinity=2.15.2` builds `_4`,
   `_5` and `_6` (May 2025 on) ship a ParaFly compiled without OpenMP, so
   phase 2 runs **one component at a time** whatever `--CPU` says. Builds
   `_0`-`_3` are fine. ORP's `orp_trinity` env was `_6`.
2. **Overhead in each component.** Each of the ~74k tiny components paid for
   JVM JIT warm-up, debug strings that were never printed, Chrysalis
   allocating a 464 MB k-mer table, numpy imports and a dozen extra
   processes. The fork removes those costs without changing the output.

SRR1789336, phase 2 only, 73,737 components, one exclusive 40-core Premise node:

| build | phase 2 wall |
| --- | --- |
| bioconda `_6` (what ORP ran) | 34h27m |
| same install, ParaFly rebuilt with OpenMP | 2h03m |
| upstream + reproducibility fixes (baseline) | 2h06m |
| **this fork** | **58m** |

The fork's output is byte-identical to the baseline for all 66,440
components that produce output. To make that comparison possible, Trinity's
output first had to be made reproducible: it depended on the run-directory
path and on the JVM's identity hash.

**Status:** done, verified and pushed. Nothing has been sent upstream yet.
ORP still runs stock bioconda `_6`, because no ORP change has been made.

---

## 2. Where everything is

### GitHub: github.com/macmanes-lab/trinityrnaseq_2026

| branch | contents |
| --- | --- |
| `master` | upstream v2.15.2 (`653e43a`) + the Trinity-side commits below + docs + `perf2026/` |
| `chrysalis-2026` | Chrysalis with the sparse k-mer table (the Chrysalis submodule points here) |
| `butterfly-2026` | Butterfly from upstream **`devel`** + reproducible hash codes + debug-message guard (the Butterfly submodule points here) |
| `inchworm-2026` | Inchworm (upstream `master` + 2 doc-only commits: `INCHWORM_2026.md`, phase-1 timing, hot spots and a plan, from 213 ORP runs). **No code changes yet.** The Inchworm submodule on `master` still points at upstream `c985c90`; to work on Inchworm, `git -C Inchworm fetch git@github.com:macmanes-lab/trinityrnaseq_2026.git inchworm-2026` and check it out. Repoint `.gitmodules` (as was done for Chrysalis/Butterfly) only if you start changing code |

Commits on `master` since upstream, oldest first:

| commit | what |
| --- | --- |
| `a0100bb` det-fix | deterministic scaffold ordering and SNP-bubble representative (output no longer depends on the run path) |
| `289954a` | Butterfly JVM runs C1-only; `--bfly_full_jit` restores the full JIT |
| `d2ecd81` | SuperTranscripts polish without numpy |
| `b9a3407` | fewer processes per component (Perl PATH lookups, no repeated version probes, etc.) |
| `ba72a3a` | ParaFly always compiled with OpenMP (configure.ac fixes) |
| `3402160` | submodules point at this fork's branches; rebuilt `Butterfly.jar` |
| `e9df80a` | `PERFORMANCE_2026.md` and `perf2026/` harness |
| `5ac3858` | ParaFly builds without automake on a fresh clone |
| `11bb328` | Butterfly submodule moved to a branch without the private test-data submodule |
| later | INSTALL.md, the upstream to-do list, and this file |

### In the repo

| path | what |
| --- | --- |
| `PERFORMANCE_2026.md` | write-up: causes, measurements, validation, upstream to-do |
| `INSTALL.md` | tested build/install steps, including patching ORP's env |
| `perf2026/install_into_env.sh` | overlays a built checkout onto an existing (bioconda) Trinity, with backup and `restore` |
| `experiments/` | Slurm scripts timing standalone fork Trinity against ORP's Trinity step; results in `experiments/results/` (see section 8) |
| `perf2026/harness/` | replay harness and experiment scripts (see section 5) |
| `perf2026/patches/0001-prof-*.patch` | opt-in per-command timing log (`TRINITY_PROF_LOG`), deliberately **not** on master |

### Premise (`ssh premise`)

| path | what |
| --- | --- |
| `~/trinity_eng/fork_check` | built, verified clone of this fork; use it as `SRC` for `install_into_env.sh` |
| `~/trinity_eng/src` | working Trinity clone. Branches `prof`, `det-fix`, `perf`. Chrysalis: `sparse-kmer-table`. Butterfly: `devel-stable-hash`, `devel-guard`, `devel-stable-guard` |
| `~/trinity_eng/src_upstream` | the same commits on upstream's base (`upstream-fixes`), for formatting PR patches |
| `~/trinity_eng/*.py, *.sh, *.sbatch, javashim, pyshim` | the live copies of the harness. Scripts expect to sit in `~/trinity_eng/` |
| `~/trinity_eng/Butterfly.*.jar` | jars from each experiment (`Butterfly.devel_stable_guard.jar` is the shipped one) |
| `~/trinity_eng/sample.tsv`, `sample_all.tsv` | replay samples: 1,500 seeded components, and all 73,737 |
| `~/trinity_eng/runs/` | replay outputs, ~250 GB. `base5` = baseline, `perf5` = fork. **Delete when no longer needed** |
| `~/trinity_eng/patches/` | old `format-patch` output, superseded by the fork's commits |
| `~/assemblies/TIME2_SRR1789336_norm_py_5050parallel.trinity/` | phase-1 output used as replay input (`recursive_trinity.cmds`, read partitions) |
| `~/orp_envs/orp_trinity` | ORP's Trinity env (bioconda `_6`, serial ParaFly), **unmodified** |
| `~/trinityrnaseq_2026` | built clone of this fork (master `4599e21`); the `experiments/` scripts run from here (ParaFly rebuild shows as local modifications; ignore) |

### Elsewhere

- ORP repo (`~/orp` on the laptop): `NOTES.md` entry for 2026-10-05 has the
  ORP-side decisions. `docs/trinity-speedup-investigation.md` is marked
  superseded for phase 2. `experiments/trinity_phase2/` is an obsolete
  duplicate of this work; delete it.
- The original Claude Code session: "Trinity ORP butterfly bottleneck" (ORP
  project, 2026-10-05).

---

## 3. Getting set up on a new machine

```bash
git clone --recursive git@github.com:macmanes-lab/trinityrnaseq_2026.git
```

Building locally is optional, since all measurement happens on Premise. To
check that Premise is still as described here:

```bash
ssh premise 'cd ~/trinity_eng/fork_check && git log --oneline -1 && nm -D trinity-plugins/BIN/ParaFly | grep -c GOMP_ && du -sh ~/trinity_eng/runs'
```

The GOMP count should be 6. To confirm ORP is still on the serial build
(expect 0):

```bash
ssh premise 'nm -D ~/orp_envs/orp_trinity/bin/trinity-plugins/BIN/ParaFly | grep -c GOMP_'
```

---

## 4. Next steps (in priority order)

### 4.1 Fix ORP now (needs a decision)

Pick one option:

- **(a) Overlay the fork onto `orp_trinity`.** This is the full 58-minute
  version, and `restore` undoes it. See INSTALL.md, "Patching an existing
  install". It is the quickest win, but the env now differs from what the ORP
  Makefile/Dockerfile builds.
- **(b) Overlay ParaFly only** (`install_into_env.sh parafly ...`). Gives
  2 h instead of 34 h, and the assembly is unchanged.
- **(c) Pin `trinity=2.15.2=*_3`** in ORP's `Makefile`/`Dockerfile`. A
  `mamba create --dry-run` with ORP's other `orp_trinity` packages and
  `python=3.14` solves (openjdk 23.0.2). This makes the fix reproducible for
  ORP users but gives no per-component speedup.

Likely best: (c) in the ORP release, plus (a) on Premise for our own runs.
In every case, also:

- Add a **ParaFly preflight check to `oyster.py`**: fail if ParaFly runs two
  `sleep 1` commands at `-CPU 2` in more than ~1.8 s. That catches any future
  serial build.
- **Revisit ORP's lane design** (`TRINITY_PHASE1_SHARE` / `PHASE2_SHARE`,
  pairing phase 2 with Trans-ABySS). It was tuned for a 34 h serial phase 2.
  At 1-2 h, Trans-ABySS (4.5 h, mostly single-threaded) becomes the long pole.
- Every ORP Trinity timing from 2026-08-14 to 2026-10-05, in ORP's `NOTES.md`
  and `sampledata/benchmarks.md`, measured the serial build. Treat those
  phase-2 conclusions as void.

### 4.2 Upstream PRs (you file these)

The details are in "Upstream to-do" at the end of PERFORMANCE_2026.md. In
short:

1. **bioconda-recipes `recipes/trinity`.** This one matters most, because
   every bioconda user since May 2025 has the serial ParaFly. In
   `makefile.patch`, pass ParaFly
   `CFLAGS="${CFLAGS} -fopenmp" CXXFLAGS="${CXXFLAGS} -fopenmp"`, bump the
   build number, and add a test:
   `nm -D $PREFIX/bin/trinity-plugins/BIN/ParaFly | grep -q GOMP_`.
2. **trinityrnaseq/trinityrnaseq:** det-fix, C1 JIT, numpy-free polish, fewer
   processes, the two ParaFly commits. They are independent of each other.
   Also ask upstream to point the Butterfly submodule at the commit the jar is
   built from (it points at 2019 `master`; the jar is built from 2022
   `devel`).
3. **trinityrnaseq/Chrysalis:** the sparse k-mer table (`chrysalis-2026`).
4. **trinityrnaseq/Butterfly** (`devel`): reproducible hash codes, then the
   debug-message guard (`butterfly-2026`), then a jar rebuild.

`~/trinity_eng/src_upstream` has the Trinity commits on upstream's base, ready
for `git format-patch`.

### 4.3 Optional follow-ups

- Run an end-to-end ORP job on SRR1789336 with the fork overlaid, to get a
  whole-pipeline number (only phase 2 was replayed).
- Phase 1 (Inchworm/Chrysalis on the full read set) was not touched. The
  pre-October analysis of phase 1 in the ORP doc is still valid.
- Fix the non-raw regex strings in `Analysis/SuperTranscripts/pylib`, which
  Python 3.14 warns about.
- Remaining per-component cost is mostly JVM start-up and Butterfly itself.
  The next step would be batching several components per JVM, which is a
  much larger change.

---

## 5. Re-running the measurements

All of this runs on Premise, in the `macmanes` Slurm partition, on whole
exclusive nodes. The scripts hard-code `~/trinity_eng` and
`~/orp_envs/orp_trinity`. The live copies are in `~/trinity_eng/`; the repo's
`perf2026/harness/` holds the same files.

1. **Make a sample**, or reuse `sample.tsv` / `sample_all.tsv`:
   ```bash
   python3 ~/trinity_eng/replay.py setup --ref ~/assemblies/TIME2_SRR1789336_norm_py_5050parallel.trinity --n 1500 --seed 1 --out ~/trinity_eng/sample.tsv
   ```
2. **Sample replay** (stages the components, runs ParaFly, compares
   outputs). `TRINITY=` selects the Trinity under test:
   ```bash
   TRINITY=~/trinity_eng/fork_check/Trinity sbatch ~/trinity_eng/replay.sbatch mytag ~/trinity_eng/runs 38
   ```
3. **Full replay** (all 73,737 components, launched the way ORP launches
   them, via `conda run`):
   ```bash
   TRINITY=~/trinity_eng/fork_check/Trinity sbatch ~/trinity_eng/full_replay.sbatch mytag ~/trinity_eng/runs 40
   ```
4. **Summarize** CPU per stage and java/python calls:
   ```bash
   python3 ~/trinity_eng/analyze.py ~/trinity_eng/runs/mytag
   ```

`build_bfly.sh OUT.jar` rebuilds Butterfly from `~/trinity_eng/src/Butterfly`.
`pf_fix_test.sh` reproduces the ParaFly configure bug. `isolate.sh`,
`envtest2.sh`, `bisect_guard.sh` and `heavy_jit.sh` are the determinism and
JIT experiments.

---

## 6. Pitfalls (each of these cost time)

- **Compare against the reproducible baseline, not production output.** Stock
  Trinity's output varies with the run directory (SuperTranscripts picks the
  bubble representative by Python `id()`) and, for ~0.15% of components, with
  the JVM identity hash (Butterfly HashMap order). Compare fork runs against
  `runs/base5`, which has the det-fix and the Butterfly hash fix, not
  against the phase-1 directory's own outputs.
- **Butterfly source is `devel`, not `master`.** Upstream's submodule pin
  (2019 `master`) does not match the shipped jar (2022 `devel`, `d3cb730`).
  `devel` built unmodified reproduces the shipped jar.
- **Butterfly jar build:** `javac --release 8`, with the classes overlaid
  onto the previous fat jar so its bundled dependencies are kept
  (`build_bfly.sh`).
- **No `autoheader` on Premise compute nodes:** use `make no_bamsifter`
  there; bamsifter is only for genome-guided runs.
- **ParaFly and automake:** a fresh clone used to trigger automake rebuild
  rules (mtimes) and fail without `aclocal-1.16`. Fixed by
  `AM_MAINTAINER_MODE` in `5ac3858`.
- **Butterfly's `Butterfly_ext_tests` submodule** points at a private
  Broad repo, which broke `git clone --recursive`. It is dropped on
  `butterfly-2026`.
- **Locale is not the issue.** `COMMON.pm` already sets `LC_ALL=C` for
  `sort`. An apparent early locale effect was actually the run-path
  dependence.
- **Always check ParaFly for GOMP symbols** before timing anything.
- **Pushing from the laptop:** the `https` origin has no stored credentials.
  Push with the SSH address
  (`git push git@github.com:macmanes-lab/trinityrnaseq_2026.git master`), or
  set the remote to SSH.

---

## 7. Log

Newest first. Add an entry when you change the state above.

- **2026-10-06 (later):** standalone fork Trinity run on 5 ORP-corrected
  samples (jobs 1320555 tasks 1-3, 1320560 tasks 4-5; all exit 0); results in
  section 8 and `experiments/results/`. `inchworm-2026` branch pushed.

- **2026-10-06:** this handoff doc (replaces `NOTES_2026.md`).
- **2026-10-05:** work moved here from the ORP repo
  (`experiments/trinity_phase2/`). INSTALL.md added and tested on Premise.
  Full replay: base5 2h06m, perf5 58m, 66,440/66,440 identical. Serial
  ParaFly in bioconda `_4`-`_6` found and confirmed (34h27m -> 2h03m with
  OpenMP).

---

## 8. Standalone fork vs ORP's Trinity step (2026-10-06)

Fork (`4599e21`, OpenMP ParaFly) on 40 cores, run from `experiments/` on the
ORP-corrected reads, against the Trinity times in the ORP logs. Full table:
`experiments/results/comparison.tsv`; raw rows: `experiments/results/timings.tsv`.

| sample | ORP p1 h | ORP p2 h | ORP total h | fork total h | p2 speedup | total speedup |
| --- | --- | --- | --- | --- | --- | --- |
| ERR058009 | 1.11 | 5.11 | 6.22 | 1.02 | 34.3x | 6.1x |
| ERR1674585 | 0.93 | 37.72 | 38.65 | 1.93 | 32.5x | 20.0x |
| SRR1789336 | 1.60 | 38.92 | 40.52 | 2.22 | 38.5x | 18.3x |
| ERR1016675 | 2.15 | 28.76 | 30.91 | 2.40 | 29.8x | 12.9x |
| DRR046632 | 2.42 | 33.28 | 35.70 | 2.67 | 39.5x | 13.4x |

- Phase 2 gains (30-40x) are real and like for like in effect (serial vs
  OpenMP ParaFly plus per-component overhead). Phase 1 is **not** like for like:
  ORP gave it 10 cores (6 for DRR046632) shared with SPAdes; the fork had 40.
- Slurm `MaxRSS` was ~123 GiB for 4 of 5 runs (ERR1674585 reported 10 GiB, not
  investigated, probably a missed child process). Peak well under 350G.
- Job map: 1320555_1 ERR1674585, _2 SRR1789336, _3 ERR058009; 1320560_4
  ERR1016675, _5 DRR046632. Tasks 4-5 were resubmitted with `--mem=350G`
  because no idle node had 700G free; `trinity_standalone.sbatch` still says
  700G. `compare_timings.py` reads `timings.tsv`, so job IDs do not matter to it.
- Not yet done: a same-core-count phase-1 comparison, and running stock Trinity
  (`TAG=stock TRINITY_SRC=... ./submit.sh`) as a third arm.
