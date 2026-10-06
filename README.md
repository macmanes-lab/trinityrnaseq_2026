trinityrnaseq
=============

Trinity RNA-Seq de novo transcriptome assembly see the Trinity [wiki](https://github.com/trinityrnaseq/trinityrnaseq/wiki)

> **Development version.** This fork is an experimental, in-progress effort to make Trinity faster. It is not an official Trinity release, and nothing in it has been accepted upstream yet. For production assemblies use the official release.

**This fork** (macmanes-lab/trinityrnaseq_2026) adds phase-2 performance and reproducibility fixes to v2.15.2: phase 2 of a 73,737-component run goes from 34 h (bioconda build with a serial ParaFly) or 2 h (working ParaFly) to under 1 h on 40 cores, with unchanged output. See [PERFORMANCE_2026.md](PERFORMANCE_2026.md), [INSTALL.md](INSTALL.md) to build and install it, and [HANDOFF.md](HANDOFF.md) to pick up the work.

## Contributing

We encourage you to contribute to Trinity! Please check out the [Contributing](https://github.com/trinityrnaseq/trinityrnaseq/wiki/Contributing) for the guidelines.
