# Installing trinityrnaseq_2026

> **Development version.** This fork is an experimental, in-progress effort to make Trinity faster. It is not an official Trinity release, and nothing in it has been accepted upstream yet. For production assemblies use the official release.

Tested 2026-10-05 on Premise: a fresh clone built cleanly, and a full Trinity
run on the bundled sample data succeeded (exit 0, 77 transcripts, 16 s).

## Requirements

The same as Trinity 2.15.2.

- **Build:** a C++ compiler with OpenMP (gcc), cmake and make.
- **Run:** Perl, Python 3, Java 8 or later, and jellyfish 2, bowtie2,
  samtools (1.3 or later) and salmon on `PATH`. On Premise the
  `~/orp_envs/orp_trinity` env has all of these.

## 1. Clone, with the fork's Chrysalis and Butterfly

```bash
git clone --recursive https://github.com/macmanes-lab/trinityrnaseq_2026.git
```

`.gitmodules` points Chrysalis at branch `chrysalis-2026` and Butterfly at
`butterfly-2026` of this repository. For an existing clone, run
`git pull && git submodule sync --recursive && git submodule update --init --recursive` instead.
If `make` stops with "No targets specified and no makefile found" in `Chrysalis` or
`Inchworm`, the submodules were not checked out; run that same command.

## 2. Build

```bash
cd trinityrnaseq_2026 && make -j 8
```

`make` also builds bamsifter, which only genome-guided runs use, and that
needs autoconf's `autoheader`. Premise's compute nodes don't have it, so
build everything else there with:

```bash
make -j 8 no_bamsifter
```

## 3. Check that ParaFly has OpenMP

The count must be above 0 (it is 6). If it is 0, phase 2 runs one component
at a time. See PERFORMANCE_2026.md section 1.

```bash
nm -D trinity-plugins/BIN/ParaFly | grep -c GOMP_
```

## 4. Test on the sample data

```bash
export PATH=$HOME/orp_envs/orp_trinity/bin:$PATH
```

```bash
cd sample_data/test_Trinity_Assembly && ../../Trinity --seqType fq --left reads.left.fq.gz --right reads.right.fq.gz --SS_lib_type RF --max_memory 4G --CPU 8 --output /tmp/test_trinity
```

After that, run `/path/to/trinityrnaseq_2026/Trinity` as usual. There are two
new options:

- `--bfly_full_jit` turns the JVM's full JIT back on for Butterfly. The
  default is now C1 only.
- `CHRYSALIS_KMER_TABLE=dense|sparse` (environment) forces either kind of
  k-mer table in GraphFromFasta.

## Patching an existing install (bioconda, ORP)

`oyster.py` always uses the `orp_trinity` env. Patch that env in place from a
built clone instead of installing Trinity separately. The script backs up
every file it replaces.

ParaFly only (the assembly is unchanged; this is the 34 h -> 2 h fix):

```bash
SRC=$HOME/trinityrnaseq_2026 $HOME/trinityrnaseq_2026/perf2026/install_into_env.sh parafly $HOME/orp_envs/orp_trinity/bin
```

Everything (ParaFly, Trinity scripts, Chrysalis, Butterfly.jar; about 2 h -> 1 h):

```bash
SRC=$HOME/trinityrnaseq_2026 $HOME/trinityrnaseq_2026/perf2026/install_into_env.sh full $HOME/orp_envs/orp_trinity/bin
```

Put the stock files back:

```bash
$HOME/trinityrnaseq_2026/perf2026/install_into_env.sh restore $HOME/orp_envs/orp_trinity/bin
```

`SRC` must be a built checkout. The script refuses a ParaFly that lacks
OpenMP. It applies the Trinity-side changes as a patch, so local package edits
are kept, such as bioconda's trimmomatic paths. It replaces binaries by
renaming, so a running job keeps the old inode.
