#!/usr/bin/env python3
"""Standalone-Trinity timings vs Trinity inside ORP, from the logs.

  python3 compare_timings.py                 # prints a TSV, also writes comparison.tsv
  ORP_LOGS=... STANDALONE=... python3 compare_timings.py

Standalone times come from trinity_standalone/timings.tsv (latest row per id);
ORP times come from the "run_trinity_phase1/2 -- done ... (Ns)" lines in the
per-sample ORP logs. ORP ran the phases on shares of a node alongside other
assemblers, and (until the ParaFly fix) with a serial ParaFly, so the CPU counts
are shown too.
"""
import csv, os, re, sys

BASE = "/mnt/home/macmaneslab/macmanes/compare"
ORP_LOGS = os.environ.get("ORP_LOGS", f"{BASE}/orp_runs/logs")
STANDALONE = os.environ.get("STANDALONE", f"{BASE}/trinity_standalone")

DONE = re.compile(r"=== run_trinity_phase([12]) -- done .*\((\d+)s\)")
CMD = re.compile(r"Trinity .*--CPU (\d+)")

def orp(id_):
    p1 = p2 = None
    cpus = []
    try:
        with open(os.path.join(ORP_LOGS, f"{id_}.log"), errors="replace") as fh:
            for line in fh:
                m = DONE.search(line)
                if m:
                    if m.group(1) == "1": p1 = int(m.group(2))
                    else: p2 = int(m.group(2))
                m = CMD.search(line)
                if m and "--no_distributed_trinity_exec" not in line:
                    cpus.append(int(m.group(1)))
                elif m:
                    cpus.insert(0, int(m.group(1)))
    except FileNotFoundError:
        pass
    return p1, p2, cpus[:2]

def h(s):
    return "NA" if s in (None, "NA", "") else f"{int(s)/3600:.2f}"

rows = {}
try:
    with open(os.path.join(STANDALONE, "timings.tsv")) as fh:
        for r in csv.DictReader(fh, delimiter="\t"):
            rows[r["id"]] = r          # later rows win
except FileNotFoundError:
    sys.exit(f"no {STANDALONE}/timings.tsv yet")

cols = ["id", "sa_cpu", "sa_phase1_h", "sa_phase2_h", "sa_total_h", "orp_cpu(p1/p2)",
        "orp_phase1_h", "orp_phase2_h", "orp_total_h", "speedup_phase2", "speedup_total", "sa_transcripts"]
out = []
for id_, r in rows.items():
    p1, p2, cpus = orp(id_)
    otot = p1 + p2 if p1 is not None and p2 is not None else None
    sp2 = f"{p2/float(r['phase2_s']):.1f}" if p2 and r["phase2_s"] not in ("NA", "") and float(r["phase2_s"]) else "NA"
    stot = f"{otot/float(r['total_s']):.1f}" if otot and float(r["total_s"]) else "NA"
    out.append([id_, r["cpu"], h(r["phase1_s"]), h(r["phase2_s"]), h(r["total_s"]),
                "/".join(map(str, cpus)) or "NA", h(p1), h(p2), h(otot), sp2, stot, r["n_transcripts"]])

with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "comparison.tsv"), "w") as fh:
    w = csv.writer(fh, delimiter="\t"); w.writerow(cols); w.writerows(out)
w = csv.writer(sys.stdout, delimiter="\t"); w.writerow(cols); w.writerows(out)
