#!/usr/bin/env python3
"""Splits V4 por familias + checks + SHA-256 de FINAL_TEST_V4."""
import csv
import hashlib
import random
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent

def norm(s: str) -> str:
    s = s.strip().lower()
    s = re.sub(r"^[\s\"'“”‘’«»¿?¡!.,;:()\[\]-]+|[\s\"'“”‘’«»¿?¡!.,;:()\[\]-]+$", "", s)
    return re.sub(r"\s+", " ", s)

def load(name):
    with open(HERE / name, encoding="utf-8") as f:
        return list(csv.DictReader(f))

pool = load("pool.csv")
final = load("final_new.csv")
legacy = load("obs_legacy.csv")
v2f = load("obs_v2final.csv")
v3f = load("obs_v3final.csv")

# ---- exact leakage de FINAL (autoría manual) ----
pool_norms = {norm(r["text"]) for r in pool}
obs_norms = {norm(r["text"]) for r in legacy} | {norm(r["text"]) for r in v2f} | {norm(r["text"]) for r in v3f}
bad = 0
for r in final:
    n = norm(r["text"])
    if n in pool_norms or n in obs_norms:
        print(f"DUP final: {r['text'][:70]}")
        bad += 1
if bad:
    print("ERROR_DATA_LEAKAGE (final debe reescribirse a mano)")
    sys.exit(1)
print("exact leakage final: OK")

# ---- pool sin observados ----
pool = [r for r in pool if norm(r["text"]) not in obs_norms]
print(f"pool tras excluir observados: {len(pool)} filas")

# ---- split por familias (seed 21), ~70/15/... resto train ----
fams = defaultdict(list)
for r in pool:
    fams[r["family_id"]].append(r)
for fid, rs in fams.items():
    assert len({r["label"] for r in rs}) == 1, f"familia mixta {fid}"
rng = random.Random(21)
by_label = defaultdict(list)
for fid in fams:
    by_label[next(iter({r["label"] for r in fams[fid]}))].append(fid)
for lab in by_label:
    rng.shuffle(by_label[lab])

cal_fams, train_fams = set(), set()
for lab, fids in by_label.items():
    total = sum(len(fams[f]) for f in fids)
    target = int(total * 0.176)  # ~15/85 del pool (FINAL aparte ~15% del total)
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
print(f"TRAIN {len(train_rows)} fams={len(train_fams)} | CAL {len(cal_rows)} fams={len(cal_fams)} | FINAL {len(final)}")

final_fams = {r["family_id"] for r in final}
inter = (train_fams & cal_fams) | (train_fams & final_fams) | (cal_fams & final_fams)
if inter:
    print(f"ERROR_FAMILY_LEAKAGE: {sorted(inter)[:10]}")
    sys.exit(1)
print("family leakage: OK")

# ---- escribe ----
def write(name, rows, fields):
    with open(HERE / name, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in rows:
            w.writerow({k: r[k] for k in fields})

write("train.csv", train_rows, ["text", "label", "category", "family_id"])
write("calibration.csv", cal_rows, ["text", "label", "category", "family_id"])
write("final_test_v4.csv", final,
      ["id", "group", "text", "expected_raw", "family_id", "critical", "coverage", "pair"])
import json as _json
for name, rows in (("train.json", train_rows), ("calibration.json", cal_rows)):
    with open(HERE / name, "w", encoding="utf-8") as f:
        _json.dump([{"text": r["text"], "label": r["label"]} for r in rows], f, ensure_ascii=False)

h = hashlib.sha256((HERE / "final_test_v4.csv").read_bytes()).hexdigest()
print(f"FINAL_TEST_V4_SHA256={h}")
(HERE / "FINAL_SHA256.txt").write_text(f"FINAL_TEST_V4_SHA256={h}\n")
print("dist train:", dict(Counter(r["label"] for r in train_rows)))
print("dist cal:", dict(Counter(r["label"] for r in cal_rows)))
print("dist final:", dict(Counter(r["expected_raw"] for r in final)))
print("final groups:", dict(Counter(r["group"] for r in final)))
print("critical:", sum(1 for r in final if r["critical"] == "1"),
      "coverage:", sum(1 for r in final if r["coverage"] == "1"),
      "pairs:", sum(1 for r in final if r["pair"]) // 2)
