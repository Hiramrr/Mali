#!/usr/bin/env python3
"""Splits action-classifier por familias + SHA FINAL_ACTION_TEST."""
import csv
import hashlib
import random
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent

def norm(s):
    s = s.strip().lower()
    s = re.sub(r"^[\s\"'“”‘’«»¿?¡!.,;:()\[\]-]+|[\s\"'“”‘’«»¿?¡!.,;:()\[\]-]+$", "", s)
    return re.sub(r"\s+", " ", s)

def load(name):
    with open(HERE / name, encoding="utf-8") as f:
        return list(csv.DictReader(f))

pool = load("pool.csv")
fa1 = load("final_A1.csv")
fa2 = load("final_A2.csv")
fub = load("final_UB.csv")
final = fa1 + fa2 + fub
print(f"FINAL bruto: {len(final)}", file=sys.stderr)

# ids únicos y 9 columnas
F = ['id','group','text','expected','family_id','uns','conf','para','short']
seen = set()
for r in final:
    assert set(r.keys()) == set(F), r.keys()
    assert r['id'] not in seen, f"dup id {r['id']}"
    seen.add(r['id'])

# exact leakage final vs pool
pool_norms = {norm(r["text"]) for r in pool}
bad = [r for r in final if norm(r["text"]) in pool_norms]
for r in bad:
    print(f"DUP final vs pool: {r['id']} {r['text'][:60]}", file=sys.stderr)
if bad:
    print("ERROR_EXACT_LEAKAGE", file=sys.stderr)
    sys.exit(1)
print("exact leakage: OK", file=sys.stderr)

# split pool por familias 80/20 (seed 99)
fams = defaultdict(list)
for r in pool:
    fams[r["family_id"]].append(r)
for fid, rs in fams.items():
    assert len({r["label"] for r in rs}) == 1, fid
rng = random.Random(99)
by_label = defaultdict(list)
for fid in fams:
    by_label[next(iter({r["label"] for r in fams[fid]}))].append(fid)
for lab in by_label:
    rng.shuffle(by_label[lab])
cal_fams, train_fams = set(), set()
for lab, fids in by_label.items():
    total = sum(len(fams[f]) for f in fids)
    target = int(total * 0.20)
    acc = 0
    for f in fids:
        if acc < target:
            cal_fams.add(f)
            acc += len(fams[f])
        else:
            train_fams.add(f)

def rows_of(fset):
    out = []
    for f in sorted(fset):
        out.extend(fams[f])
    return out

train_rows = rows_of(train_fams)
cal_rows = rows_of(cal_fams)
print(f"TRAIN {len(train_rows)} fams={len(train_fams)} | CAL {len(cal_rows)} fams={len(cal_fams)} | FINAL {len(final)}", file=sys.stderr)

final_fams = {r["family_id"] for r in final}
inter = (train_fams & cal_fams) | (train_fams & final_fams) | (cal_fams & final_fams)
if inter:
    print(f"ERROR_FAMILY_LEAKAGE: {sorted(inter)[:10]}", file=sys.stderr)
    sys.exit(1)
print("family leakage: OK", file=sys.stderr)

def write(name, rows, fields):
    with open(HERE / name, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in rows:
            w.writerow({k: r[k] for k in fields})

write("train.csv", train_rows, ["text", "label", "category", "family_id"])
write("calibration.csv", cal_rows, ["text", "label", "category", "family_id"])
write("final_action_test.csv", final, F)
import json as _json
for name, rows in (("train.json", train_rows), ("calibration.json", cal_rows)):
    with open(HERE / name, "w", encoding="utf-8") as f:
        _json.dump([{"text": r["text"], "label": r["label"]} for r in rows], f, ensure_ascii=False)

h = hashlib.sha256((HERE / "final_action_test.csv").read_bytes()).hexdigest()
print(f"FINAL_ACTION_TEST_SHA256={h}")
(HERE / "FINAL_SHA256.txt").write_text(f"FINAL_ACTION_TEST_SHA256={h}\n")
print("dist train:", dict(Counter(r["label"] for r in train_rows)), file=sys.stderr)
print("dist cal:", dict(Counter(r["label"] for r in cal_rows)), file=sys.stderr)
print("dist final:", dict(Counter(r["expected"] for r in final)), file=sys.stderr)
print("final groups:", dict(Counter(r["group"] for r in final)), file=sys.stderr)
print("uns:", sum(1 for r in final if r["uns"] == "1"),
      "conf:", sum(1 for r in final if r["conf"] == "1"),
      "para:", sum(1 for r in final if r["para"] == "1"),
      "short:", sum(1 for r in final if r["short"] == "1"), file=sys.stderr)
