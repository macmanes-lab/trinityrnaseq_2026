# Inchworm engineering notes (2026)

Branch `inchworm-2026`, started 2026-10-06 from upstream Inchworm `c985c90`
(the commit Trinity v2.15.2 pins). This follows the same pattern as
`chrysalis-2026` and `butterfly-2026` in the Trinity fork. Nothing has been
changed yet. This file is the analysis and plan.

## 1. How much time is at stake

The SRR1789336 phase-1 run on Premise (`~/assemblies/TIME2_SRR1789336_norm_py_5050parallel.trinity`,
Aug 19, `--CPU 20 --inchworm_cpu 10`), using file mtimes (start = mtime of
`Trinity.timing`, so the first row is approximate):

| stage | from | to | wall |
| --- | --- | --- | --- |
| in-silico normalization + fq->fa | 07:53 | 08:22 | ~29 min |
| jellyfish count + dump + histo | 08:22 | 08:24 | ~2 min |
| **Inchworm: load 117.6M k-mers** | 08:24 | 08:27 | **~3 min** |
| **Inchworm: build contigs, write** | 08:27 | 08:29 | **~2 min** |
| Chrysalis: bowtie2-build, bowtie2, scaffolding | 08:29 | 08:40 | ~11 min |
| GraphFromFasta | 08:40 | 08:40 | <1 min |
| ReadsToTranscripts | 08:40 | 08:54 | ~14 min |
| sort + read partitioning | 08:54 | 08:58 | ~4 min |

Inchworm is about 5 of the ~65 phase-1 minutes on this (normalized) data set,
and about 4% of a whole fork run (phase 2 is now 58 min). The ceiling for
speed alone is therefore small here. It grows with input size: the hash map
cost scales with distinct k-mers, which for un-normalized or larger libraries
can be several times 117M, and memory (below) may matter more than time.

Before writing code, get a real breakdown: rerun Inchworm alone on
`jellyfish.kmers.25.asm.fa` (3.4 GB, still on Premise) with the exact phase-1
command, under `/usr/bin/time -v`, at 1, 6, 10 and 20 threads. Its stderr
prints `TIMING KMER_DB_BUILDING` and the contig-assembly time.

## 2. How Trinity runs Inchworm

- **Phase 1:** `inchworm --kmers jellyfish.kmers.25.asm.fa --run_inchworm -K 25
  --monitor 1 --DS --num_threads $inchworm_cpu --PARALLEL_IWORM
  --min_any_entropy 1.0 -L 25 --no_prune_error_kmers`.
  `inchworm_cpu` defaults to min(6, `--CPU`).
- **Phase 2** (each of ~74k components): `inchworm --reads ... --DS
  --num_threads 1`, no `--PARALLEL_IWORM`, error pruning on, k-mers counted by
  Inchworm itself and sorted by abundance. Per-component Inchworm cost did not
  show up as a significant share in the phase-2 profile (PERFORMANCE_2026.md
  section 2), so phase 2 is not the target.

## 3. Where the time and memory go (code reading)

### K-mer table (`KmerCounter`)

- `__gnu_cxx::hash_map<uint64, unsigned>` with an identity hash: a
  node-based, chained table. Each entry is a separately malloc'd node
  (~32 B with allocator overhead) plus an 8 B bucket pointer, so roughly
  40-48 B per k-mer, about 5-6 GB for 117.6M k-mers, versus 12 B of payload.
  Every lookup is a pointer chase and a likely cache miss.
- `add_kmer` takes a global `#pragma omp critical (HashMap)` for every insert.
  Loading is effectively serial, and the comment in `IRKE_run.cpp`
  ("going higher leads to decreased performance ... due to thread collisions")
  is this lock.
- The input is parsed through `Fasta_reader::getNext()`, which holds another
  critical section and builds a `std::string` header and sequence per k-mer
  record, then `atoi` on the header and `kmer_to_intval` on a string copy.
  For 117.6M two-line records this is most of the 3-minute load.
- `--DS` canonicalization calls `revcomp_val`, a 25-iteration loop, on every
  insert and **every lookup**.

### Contig building (`IRKE::compute_sequence_assemblies`, `inchworm_step`)

- Each extension step calls `get_{forward,reverse}_kmer_candidates`: 4 hash
  lookups (each with a revcomp loop), a heap-allocated `vector`, and a sort.
- `Kmer_visitor` (visited set) is a `std::set` (red-black tree), allocated per
  seed, with insert/erase on every step.
- `exceeds_min_connectivity` returns `true` immediately whenever
  `min_connectivity < 1e5`, so the connectivity test is always off. (Looks
  like an upstream bug or a deliberate disable; either way it is dead work to
  pass the arguments, and it must stay "off" to keep output identical.)
- In `--PARALLEL_IWORM` mode threads read the shared map while other threads
  zero counts (`clear_kmer` has no lock, by design). This is a data race:
  output depends on thread timing.
- Output is deduplicated through a 32-bit `generateHash` of each contig into a
  `std::map`. A hash collision silently drops a distinct contig.

### Phase 2 path (`--reads`, built-in counter)

- `add_sequence` does `sequence.substr(i, K)` per position (an allocation per
  k-mer) and re-encodes each k-mer from scratch, instead of a rolling 2-bit
  encoding.

## 4. Reproducibility caveat (affects how changes are validated)

With `--PARALLEL_IWORM` and more than one thread, seeds come from hash-iterator
order with dynamic scheduling, and threads race on clearing k-mers. Phase-1
Inchworm output is very likely **not** byte-reproducible between runs even
with the same binary. First thing to check: run the stock binary twice at 10
threads and diff `inchworm.DS.fa`. If it differs, validation has to be either

- byte-identical at `--num_threads 1` (deterministic), plus
- statistical at N threads (contig count, N50, total length, k-mer content of
  the contig set) and, ideally, identical downstream phase-1 partitioning
  stats.

Changing the hash table also changes iteration order, which changes the seed
order in parallel mode and therefore the contigs. So any table swap is not
"output-identical" in parallel mode by construction; it is only identical in
the serial, sorted path if ties in the sort are broken deterministically
(they currently are not: `std::sort` on count only).

## 5. Candidate changes, in order of value per effort

1. **Fast k-mer file loader.** Read `jellyfish dump` output with a
   hand-rolled parser over large buffered blocks (or `mmap`), split by thread
   on record boundaries, encode 2-bit directly from bytes. Removes
   `Fasta_reader`, `std::string` per record and its lock. Alternative: have
   Trinity call `jellyfish dump -c` (column format) or read the `.jf` directly.
2. **Flat open-addressing k-mer table.** `uint64 key + uint32 count` in one
   array, linear probing, a real mixing hash (identity hash is fine for a
   prime-sized chained table but terrible for power-of-two probing). Size it
   from the k-mer count, which is known up front (the dump file size or the
   jellyfish histo). Roughly 4x less memory and much better cache behavior.
   Inserts become lock-free per slot (CAS on key) or partitioned by hash bits
   into per-thread shards.
3. **Cheap canonicalization.** Bit-parallel 64-bit reverse complement
   (byte-swap plus 2-bit-pair shuffles) instead of the 25-step loop.
4. **Allocation-free extension.** Candidates into a fixed `array<,4>`
   (sorting four elements in place), visited set as a small open-addressing
   set or a vector cleared per seed.
5. **Rolling encoding in `add_sequence`** for the phase-2 path.
6. **Correctness fixes, separate commits:** 64-bit contig hash for dedup;
   deterministic tie-break (count, then k-mer value) in the seed sort.

Items 1-2 address the 3-minute load and most of the memory; 3-4 address the
2-minute build. Expected gain on SRR1789336: roughly 5 min -> 1-2 min of
Inchworm, i.e. a few minutes off phase 1. The memory reduction (~5-6 GB ->
~1.5 GB) is probably the more useful result for big libraries.

## 6. Not Inchworm, but noticed while measuring

On this run normalization takes ~29 min, the largest single phase-1 stage,
and ReadsToTranscripts + Chrysalis bowtie2 take another ~25 min. If the goal
is phase-1 wall time, those are bigger targets than Inchworm. (ORP already
normalizes its input; check whether Trinity's own `--normalize_reads` pass is
redundant for ORP runs, i.e. whether `--no_normalize_reads` is safe there.)

## 7. Next steps

1. On Premise: timing breakdown of stock Inchworm (section 1) and the
   determinism check (section 4).
2. Decide whether the few-minute gain plus memory is worth it, versus
   normalization or ReadsToTranscripts.
3. If yes: implement 1-4 on this branch, validate per section 4, then point
   the Trinity fork's Inchworm submodule at `inchworm-2026`.
