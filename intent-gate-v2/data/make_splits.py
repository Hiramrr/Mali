#!/usr/bin/env python3
"""Split por familias + verificaciones. Orden: FINAL existe antes de entrenar.

1. Exact-leakage entre pool / final_new / legacy -> ERROR_DATA_LEAKAGE
2. Split pool en TRAIN/CALIBRATION por familias (seed 7), ~82/18 por label
3. Family-leakage entre TRAIN/CAL/FINAL -> ERROR_FAMILY_LEAKAGE
4. Escribe train.csv, calibration.csv, final_test_v2.csv + SHA-256
"""
import csv
import hashlib
import random
import re
import shutil
import sys
from collections import defaultdict
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
legacy = load("legacy_diagnostic_holdout.csv")
legacy_texts = [r["text"] if "text" in r else r.get("TEXT", "") for r in legacy]

# ---- 1a. exact leakage de FINAL (autoría manual: debe corregirse a mano) ----
def check_exact(rows, name, ref_sets):
    bad = 0
    for r in rows:
        n = norm(r["text"])
        for refname, ref in ref_sets:
            if n in ref:
                print(f"DUP {name} vs {refname}: {r['text'][:70]}")
                bad += 1
    return bad

pool_norms = {norm(r["text"]) for r in pool}
final_norms = {norm(r["text"]) for r in final}
legacy_norms = {norm(t) for t in legacy_texts}
if check_exact(final, "final", [("pool", pool_norms), ("legacy", legacy_norms)]):
    print("ERROR_DATA_LEAKAGE (final debe reescribirse a mano)")
    sys.exit(1)
print("exact leakage final: OK")

# ---- 1b. el pool generado no puede contener frases legacy: se excluyen ----
pool = [r for r in pool if norm(r["text"]) not in legacy_norms]
pool_norms = {norm(r["text"]) for r in pool}
print(f"pool tras excluir legacy: {len(pool)} filas")

# ---- 2. family split del pool ----
fams = defaultdict(list)
for r in pool:
    fams[r["family_id"]].append(r)
fam_ids = sorted(fams)
rng = random.Random(7)
rng.shuffle(fam_ids)

def label_of(fid):
    labs = {r["label"] for r in fams[fid]}
    assert len(labs) == 1, f"familia mixta {fid}"
    return next(iter(labs))

# Asigna por label para balance: acumula familias a CAL hasta ~18% de ejemplos.
by_label = defaultdict(list)
for fid in fam_ids:
    by_label[label_of(fid)].append(fid)

cal_fams, train_fams = set(), set()
for lab, fids in by_label.items():
    total = sum(len(fams[f]) for f in fids)
    target = int(total * 0.18)
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
print(f"TRAIN: {len(train_rows)} fams={len(train_fams)} | "
      f"CAL: {len(cal_rows)} fams={len(cal_fams)} | FINAL: {len(final)}")

# ---- 3. family leakage ----
final_fams = {r["family_id"] for r in final}
inter = (train_fams & cal_fams) | (train_fams & final_fams) | (cal_fams & final_fams)
if inter:
    print(f"ERROR_FAMILY_LEAKAGE: {sorted(inter)[:10]}")
    sys.exit(1)
print("family leakage: OK (intersecciones vacías)")

# ---- 4. escribe + hash ----
def write(name, rows):
    with open(HERE / name, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["text", "label", "category", "family_id"])
        w.writeheader()
        w.writerows({k: r[k] for k in ("text", "label", "category", "family_id")} for r in rows)

def write_final(rows):
    with open(HERE / "final_test_v2.csv", "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["id", "group", "text", "expected_raw",
                                          "expected_gate", "family_id", "critical"])
        w.writeheader()
        w.writerows(rows)

write("train.csv", train_rows)
write("calibration.csv", cal_rows)
write_final(final)
import json as _json
for name, rows in (("train.json", train_rows), ("calibration.json", cal_rows)):
    with open(HERE / name, "w", encoding="utf-8") as f:
        _json.dump([{"text": r["text"], "label": r["label"], "category": r["category"],
                     "family_id": r["family_id"]} for r in rows], f, ensure_ascii=False)
h = hashlib.sha256((HERE / "final_test_v2.csv").read_bytes()).hexdigest()
print(f"FINAL_TEST_V2_SHA256={h}")
(HERE / "FINAL_SHA256.txt").write_text(f"FINAL_TEST_V2_SHA256={h}\n")

def dist(rows):
    from collections import Counter
    c = Counter(r["label"] for r in rows)
    return f"C={c['EDITOR_CONTROL']} D={c['DICTATION']}"
print("dist train:", dist(train_rows))
print("dist cal:", dist(cal_rows))
fc = [r for r in final if r["expected_gate"] == "NO_CONTROL"]
fcc = [r for r in final if r["expected_gate"] == "CONTROL"]
print(f"dist final: NO_CONTROL={len(fc)} CONTROL={len(fcc)} critical={sum(1 for r in final if r['critical']=='1')}")
