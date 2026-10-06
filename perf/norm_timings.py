"""Normalization sub-step wall times from ORP sample logs. Usage: ssh premise python3 - LOGDIR < norm_timings.py"""
import glob, os, re, sys
from datetime import datetime
TS1 = re.compile(r"^\w+day, (\w+ \d+, \d{4}): (\d\d:\d\d:\d\d)\tCMD: (.*)")
KEYS = [("seqtk", r"seqtk-trinity seq"), ("jf_count", r"jellyfish count"), ("jf_histo", r"jellyfish histo"),
        ("jf_dump", r"jellyfish dump"), ("fkcs", r"fastaToKmerCoverageStats"), ("sort", r"sort --parallel"),
        ("merge", r"nbkc_merge_left_right_stats"), ("normalize", r"nbkc_normalize\.pl"), ("cat", r"^cat ")]
PAR = {"seqtk", "fkcs", "sort"}  # run as left/right pairs in parallel: take max
print("\t".join(["sample", "norm"] + [k for k, _ in KEYS] + ["capture_etc"]))
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.log"))):
    s = os.path.basename(f)[:-4]
    if s.startswith("orp_"): continue
    L = open(f, errors="replace").read().split("\n")
    st = [i for i, l in enumerate(L) if l.startswith("=== run_trinity_phase1 -- start")]
    if not st: continue
    seg = L[st[-1]:]
    a = b = None; ta = tb = None
    for i, l in enumerate(seg):
        m = TS1.match(l)
        if m and a is None and "insilico_read_normalization.pl" in m.group(3):
            a, ta = i, datetime.strptime(m.group(1) + " " + m.group(2), "%B %d, %Y %H:%M:%S")
        if m and a is not None and "normalization.ok" in m.group(3):
            b, tb = i, datetime.strptime(m.group(1) + " " + m.group(2), "%B %d, %Y %H:%M:%S"); break
    if b is None: continue
    pend, dur = [], {}
    for l in seg[a + 1:b]:
        j = l.find("CMD: ")
        if j >= 0 and not TS1.match(l):
            pend.append(l[j + 5:])
        m = re.search(r"CMD finished \((\d+) seconds\)", l)
        if m and pend:
            c = pend.pop(0)
            for k, p in KEYS:
                if re.search(p, c):
                    dur.setdefault(k, []).append(int(m.group(1))); break
    tot = (tb - ta).total_seconds()
    vals = {k: (max(v) if k in PAR else sum(v)) for k, v in dur.items()}
    rest = tot - sum(vals.values())
    print("\t".join([s, str(int(tot))] + [str(vals.get(k, "")) for k, _ in KEYS] + [str(int(rest))]))
