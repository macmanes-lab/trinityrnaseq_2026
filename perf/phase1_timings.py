#!/usr/bin/env python3
"""Per-stage Trinity phase-1 wall times from ORP sample logs (logs/<SAMPLE>.log).
Usage: ssh premise python3 - LOGDIR < phase1_timings.py"""
import glob, os, re, sys
from datetime import datetime

LOGDIR = sys.argv[1]

TS1 = re.compile(r"^\w+day, (\w+ \d+, \d{4}): (\d\d:\d\d:\d\d)\tCMD: (.*)")
TS2 = re.compile(r"^\* \[\w{3} (\w{3}) +(\d+) (\d\d:\d\d:\d\d) (\d{4})\] Running CMD: (.*)")
ORP = re.compile(r"^=== run_trinity_phase1 -- (start|done) (\S+ \S+)")


def parse_cmds(lines):
    out = []
    for ln in lines:
        m = TS1.match(ln)
        if m:
            out.append((datetime.strptime(m.group(1) + " " + m.group(2), "%B %d, %Y %H:%M:%S"), m.group(3)))
            continue
        m = TS2.match(ln)
        if m:
            t = datetime.strptime("%s %s %s %s" % (m.group(1), m.group(2), m.group(4), m.group(3)), "%b %d %Y %H:%M:%S")
            out.append((t, m.group(5)))
    return out


def first(cmds, pat, after=None):
    for t, c in cmds:
        if (after is None or t >= after) and re.search(pat, c):
            return t
    return None


def last(cmds, pat):
    r = None
    for t, c in cmds:
        if re.search(pat, c):
            r = t
    return r


rows = []
for f in sorted(glob.glob(os.path.join(LOGDIR, "*.log"))):
    sample = os.path.basename(f)[:-4]
    if sample.startswith("orp_"):
        continue
    lines = open(f, errors="replace").read().split("\n")
    # restrict to the last phase-1 attempt
    starts = [i for i, l in enumerate(lines) if l.startswith("=== run_trinity_phase1 -- start")]
    if not starts:
        continue
    seg = lines[starts[-1]:]
    end_i = next((i for i, l in enumerate(seg) if l.startswith("=== run_trinity_phase1 -- done")), None)
    if end_i is None:
        continue
    seg = seg[: end_i + 1]
    p1_start = datetime.strptime(ORP.match(seg[0]).group(2), "%Y-%m-%d %H:%M:%S")
    p1_end = datetime.strptime(ORP.match(seg[end_i]).group(2), "%Y-%m-%d %H:%M:%S")
    cmds = parse_cmds(seg)

    m = {}
    m["norm"] = first(cmds, r"insilico_read_normalization\.pl")
    m["norm_ok"] = first(cmds, r"normalization\.ok")
    m["both_ok"] = first(cmds, r"both\.fa\.ok")
    m["iworm"] = first(cmds, r"Inchworm/bin//?inchworm ")
    m["iworm_done"] = first(cmds, r"inchworm\.\w*\.?fa\.finished") or first(cmds, r"mv .*inchworm.*\.tmp")
    m["bt2"] = first(cmds, r"filter_iworm_by_min_length_or_cov")
    m["scaff"] = first(cmds, r"scaffold_iworm_contigs\.pl")
    m["gff"] = first(cmds, r"Chrysalis/bin/GraphFromFasta")
    m["gff_done"] = first(cmds, r"sort .*iworm_cluster_welds_graph")
    m["rtt"] = first(cmds, r"Chrysalis/bin/ReadsToTranscripts")
    m["rtt_done"] = first(cmds, r"sort .*readsToComponents")
    m["mkdir1"] = first(cmds, r"mkdir -p .*read_partitions")
    m["part_ok"] = first(cmds, r"partitioned_reads\.files\.list\.ok")

    def d(a, b):
        return (m[b] - m[a]).total_seconds() if m.get(a) and m.get(b) else None

    text = "\n".join(seg)
    # fastaToKmerCoverageStats / inchworm "done parsing N Kmers ... taking S seconds"
    banner = text.find("Inchworm (K=")
    pre = text[:banner] if banner > 0 else text
    post = text[banner:] if banner > 0 else ""
    fk = [int(x) for x in re.findall(r"done parsing \d+ Kmers.*?taking (\d+) seconds", pre)]
    nk = re.findall(r"done parsing (\d+) Kmers", pre)
    sel = re.search(r"(\d+) / (\d+) = [\d.]+% reads selected", text)
    tim = dict((k, int(v)) for k, v in re.findall(r"TIMING (\w+) (\d+) s\.", post))
    iwk = re.search(r"done parsing (\d+) Kmers", post)
    mk = len(re.findall(r"CMD: mkdir -p .*read_partitions", text))
    cpu = re.search(r"--CPU (\d+) --inchworm_cpu (\d+)", text)

    rows.append(dict(
        sample=sample,
        cpu=cpu.group(1) if cpu else "",
        p1=(p1_end - p1_start).total_seconds(),
        pre=(m["norm"] - p1_start).total_seconds() if m["norm"] else None,
        norm=d("norm", "norm_ok"),
        fkcs=max(fk) if fk else None,
        norm_kmers=int(nk[0]) if nk else None,
        reads_in=int(sel.group(2)) if sel else None,
        reads_sel=int(sel.group(1)) if sel else None,
        tofa=d("norm_ok", "both_ok"),
        jelly=d("both_ok", "iworm"),
        iworm=d("iworm", "iworm_done"),
        iw_load=tim.get("KMER_DB_BUILDING"),
        iw_prune=tim.get("PRUNING"),
        iw_build=tim.get("CONTIG_BUILDING"),
        iw_kmers=int(iwk.group(1)) if iwk else None,
        bt2=d("bt2", "scaff"),
        scaff=d("scaff", "gff"),
        gff=d("gff", "gff_done"),
        misc=d("gff_done", "rtt"),
        rtt=d("rtt", "rtt_done"),
        sort=d("rtt_done", "mkdir1"),
        mkdir=d("mkdir1", "part_ok"),
        n_mkdir=mk,
        tail=(p1_end - m["part_ok"]).total_seconds() if m["part_ok"] else None,
    ))

cols = ["sample", "cpu", "p1", "pre", "norm", "fkcs", "norm_kmers", "reads_in", "reads_sel", "tofa", "jelly",
        "iworm", "iw_load", "iw_prune", "iw_build", "iw_kmers", "bt2", "scaff", "gff", "misc", "rtt", "sort",
        "mkdir", "n_mkdir", "tail"]
print("\t".join(cols))
for r in rows:
    print("\t".join("" if r[c] is None else (str(int(r[c])) if isinstance(r[c], float) else str(r[c])) for c in cols))
