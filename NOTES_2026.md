# Working notes: where the 2026 performance work stands

Handoff notes for picking this up on another machine. The results are in
[PERFORMANCE_2026.md](PERFORMANCE_2026.md) and the install steps in
[INSTALL.md](INSTALL.md). This file covers state and next steps. Newest
entries go on top.

## 2026-10-05: state at end of day

**What's done.** Everything is pushed to github.com/macmanes-lab/trinityrnaseq_2026.

- `master`: upstream v2.15.2 (653e43a) plus these changes: det-fix, Butterfly
  C1 JIT (`--bfly_full_jit`), numpy-free SuperTranscripts polish, fewer
  processes per component, ParaFly always built with OpenMP, ParaFly
  buildable without automake, rebuilt `Butterfly.jar`, `PERFORMANCE_2026.md`,
  `INSTALL.md` and `perf2026/` (install script, harness, profiling patch).
- `chrysalis-2026`: sparse k-mer table for small inputs.
- `butterfly-2026`: upstream Butterfly `devel` plus reproducible hash codes and
  the debug-message guard. The private `Butterfly_ext_tests` submodule is
  removed, so `--recursive` clones work.
- Headline (SRR1789336 phase 2, 73,737 components, one 40-core node): 34h27m
  (bioconda `_6`, serial ParaFly) -> 2h03m (OpenMP ParaFly) -> **58m** (this
  fork). The fork's output is byte-identical to the reproducibility-fixed
  baseline for all 66,440 components that produce output.

**Root cause worth remembering.** Bioconda `trinity=2.15.2` builds `_4`, `_5`
and `_6` (May 2025 on) ship a ParaFly without OpenMP. `_0`-`_3` are fine.
Check any install with `nm -D .../trinity-plugins/BIN/ParaFly | grep -c GOMP_`.
Every ORP Trinity timing between 2026-08-14 and 2026-10-05 measured the
serial build.

**Next steps**

1. Upstream PRs: see "Upstream to-do" at the end of PERFORMANCE_2026.md
   (bioconda recipe first, since it affects every bioconda user; then
   trinityrnaseq, Chrysalis, Butterfly).
2. ORP-side decisions, tracked in the ORP repo's `NOTES.md`:
   - pin `trinity=2.15.2=*_3`, or install this fork into `orp_trinity`;
   - add a ParaFly preflight check to `oyster.py`;
   - rebalance the phase-1/phase-2 lanes now that Trans-ABySS is the long pole.
3. Optional: a full ORP run of SRR1789336 with
   `perf2026/install_into_env.sh full` applied to `orp_trinity`, to get an
   end-to-end number.

## Premise layout (`ssh premise`)

| path | what |
| --- | --- |
| `~/trinity_eng/fork_check` | built, verified clone of this fork (good `SRC` for `install_into_env.sh`) |
| `~/trinity_eng/src` | working Trinity clone, branches `prof` (opt-in timing log), `det-fix`, `perf`; Chrysalis branch `sparse-kmer-table`; Butterfly branches `devel-stable-hash`, `devel-guard`, `devel-stable-guard` (Butterfly source is `origin/devel`, not the stale submodule `master`) |
| `~/trinity_eng/src_upstream` | the same Trinity commits on upstream's base (`upstream-fixes`), used to format patches |
| `~/trinity_eng/Butterfly.*.jar` | Butterfly jars from each experiment |
| `~/trinity_eng/runs/` | replay runs (~250 GB): base5/perf5 sample and full replays. Delete when done |
| `~/trinity_eng/patches/` | format-patch output, superseded by the fork's commits |
| `~/assemblies/TIME2_SRR1789336_norm_py_5050parallel.trinity/` | phase-1 output used as the replay input and reference |
| `~/trinityrnaseq_2026` | an older, unbuilt clone. Pull, update submodules and build it, or use `fork_check` |

The harness scripts in `perf2026/harness/` hard-code these Premise paths.

## History

- Started in the ORP repo (session "Trinity ORP butterfly bottleneck",
  2026-10-05) as `experiments/trinity_phase2/`. Moved here the same day.
  `PERFORMANCE_2026.md` is the cleaned-up version of that write-up, and the
  `patches/` series there is superseded by this repo's commits.
