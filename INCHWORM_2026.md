# Inchworm engineering notes (2026)

Branch `inchworm-2026`, started 2026-10-06 from upstream Inchworm `c985c90`
(the commit Trinity v2.15.2 pins). This follows the same pattern as
`chrysalis-2026` and `butterfly-2026` in the Trinity fork. Nothing has been
changed yet. This file is the analysis and plan.

## 1. How much time is at stake

### Across ORP runs (213 logs)

Source: every per-sample log in Premise
`/mnt/home/macmaneslab/macmanes/compare/orp_runs/logs/` (Sept-Oct 2026, bioconda
`_6`, phase 1 at `--CPU 6` for 205 runs and `--CPU 10` for 8, alongside SPAdes on
the same node). Stage boundaries come from Trinity's timestamped `CMD:` lines;
normalization sub-steps from its `CMD finished (N seconds)` lines. Parsers and
raw tables: `perf/phase1_timings.py`, `perf/norm_timings.py`, `perf/*.tsv`.

Phase 1 wall: median 107 min, mean 133 min, max 771 min, 473 h total.

| stage | median | p90 | share of phase 1 |
| --- | --- | --- | --- |
| **in-silico normalization** | 37.7 min | 84.3 min | **37.3%** |
| **ReadsToTranscripts** (Chrysalis) | 31.5 min | 74.7 min | **29.2%** |
| bowtie2-build + bowtie2 (iworm scaffolding) | 8.3 min | 22.8 min | 8.5% |
| `scaffold_iworm_contigs.pl` | 6.0 min | 23.4 min | 7.9% |
| **Inchworm** | 5.3 min | 13.6 min | **5.2%** |
| GraphFromFasta | 4.0 min | 14.7 min | 4.8% |
| read-partition `mkdir`s | 2.8 min | 8.9 min | 3.7% |
| jellyfish (Trinity's own) | 2.5 min | 5.8 min | 2.2% |
| everything else | | | <1.5% |

Inside Inchworm: k-mer load 2.9% of phase 1 (median 185 s), contig building
1.1%, pruning 0.5%.

Inside normalization (177 h in total):

| sub-step | share of normalization | share of phase 1 |
| --- | --- | --- |
| **`fastaToKmerCoverageStats`** (Inchworm repo) | 25.1% | 9.4% |
| read capture (Perl, after `nbkc_normalize.pl`) | 22.5% | 8.4% |
| `nbkc_merge_left_right_stats.pl` (Perl, 1 thread) | 20.6% | 7.7% |
| `nbkc_normalize.pl` (Perl, 1 thread) | 12.9% | 4.8% |
| jellyfish count / dump / histo | 14.6% | 5.5% |
| seqtk fq->fa, sort, cat | 4.3% | 1.6% |

Normalization time correlates with input reads at r = 0.99. ReadsToTranscripts
and bowtie2 correlate with the reads that survive normalization (r = 0.93,
0.92).

### What this means for this branch

The Inchworm k-mer code (`KmerCounter`, `Fasta_reader`, the jellyfish-dump
loader) is used by two programs: `inchworm` (5.2% of phase 1) and
`fastaToKmerCoverageStats` (9.4%). So the realistic target is about **15% of
phase 1**, not 5%. Add the stats sort and the Perl merge, which only exist
because left and right stats are made separately, and about **25% of phase 1**
lives in code this repo owns or could absorb.

`fastaToKmerCoverageStats` specifically:

- It is run **twice in parallel, once per mate file**, and each run loads the
  **whole** k-mer table (82M k-mers, ~168 s, for SRR1789336): twice the load
  work and twice the memory.
- `MAX_THREADS = 6` is hard-coded; `--num_threads` above that is ignored.
- Per read: `substr` per k-mer, string-based `contains_non_gatc` and
  encoding, a revcomp loop per lookup, a `stringstream` per output line and a
  global critical section for `cout`.
- Its two outputs are then sorted by read name and joined by
  `nbkc_merge_left_right_stats.pl` (20.6% of normalization). A single
  invocation that takes both mate files, streams pairs together and writes
  the merged pair stats directly would remove the second load, both sorts and
  the merge script. Output must match `pairs.K25.stats` exactly
  (normalization selects reads from it).

Single-run example (SRR1789336, 2026-10-01): normalization 35 min =
fastaToKmerCoverageStats 572 s, merge 406 s, `nbkc_normalize.pl` 260 s,
capture ~490 s, jellyfish 285 s, seqtk 64 s; Inchworm 344 s (load 227,
prune 40, build 50).

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
Inchworm. The memory reduction (~5-6 GB ->
~1.5 GB) is probably the more useful result for big libraries.

## 6. Not Inchworm, but noticed while measuring

- **ReadsToTranscripts (29% of phase 1)** is Chrysalis: the next target on
  `chrysalis-2026`.
- **Normalization Perl** (`nbkc_normalize.pl` and read capture, ~13% of phase
  1) is in the Trinity repo. ORP's `--normalize-reads` is this Trinity
  normalization (ORP does not normalize separately), so it is not redundant.
- **Read-partition `mkdir`s** (3.7%): one `mkdir -p` shell-out per bin at
  ~0.34 s each. A Trinity-side fix (Perl `make_path`, or create bins lazily).

## 7. Next steps

1. Determinism check on Premise (section 4): stock `inchworm` twice at 10
   threads, and stock `fastaToKmerCoverageStats` twice (its output order
   depends on threads, but sorted output should be identical).
2. Shared k-mer layer first (items 1-3 in section 5). Both `inchworm` and
   `fastaToKmerCoverageStats` benefit.
3. Paired `fastaToKmerCoverageStats` mode that writes `pairs.K25.stats`
   directly, plus the matching change to `insilico_read_normalization.pl`
   (Trinity repo). Validate with an identical `pairs.K25.stats` and an
   identical selected-read list.
4. Then the Inchworm contig-building items, validated per section 4.
5. Point the Trinity fork's Inchworm submodule at `inchworm-2026`.
