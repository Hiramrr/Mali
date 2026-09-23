#!/usr/bin/env python3
"""Ensambla pool V4: v2 + v3 + bloques nuevos, binario, dedupe, exclusiones."""
import csv
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

def norm(s):
    import re
    s = s.strip().lower()
    s = re.sub(r"^[\s\"'“”‘’«»¿?¡!.,;:()\[\]-]+|[\s\"'“”‘’«»¿?¡!.,;:()\[\]-]+$", "", s)
    return re.sub(r"\s+", " ", s)

def load(name):
    with open(HERE / name, encoding="utf-8") as f:
        return list(csv.DictReader(f))

MAP = {"EDITOR_CONTROL": "EDITOR_CONTROL", "DICTATION": "NON_CONTROL",
       "NO_ACTION": "NON_CONTROL", "NON_CONTROL": "NON_CONTROL"}

rows = []  # (text, label, category, family)
for name, prefix in (("pool_v2.csv", "v2"), ("pool_v3.csv", "v3"), ("pool_new.csv", "")):
    for r in load(name):
        lab = MAP[r["label"]]
        fid = r["family_id"] if not prefix else f"{prefix}_{r['family_id']}"
        rows.append((r["text"].strip(), lab, r["category"], fid))

print(f"bruto: {len(rows)}", file=sys.stderr)

# observados: legacy + finales v2/v3
obs = set()
for name, col in (("obs_legacy.csv", "text"), ("obs_v2final.csv", "text"), ("obs_v3final.csv", "text")):
    for r in load(name):
        obs.add(norm(r[col]))
before = len(rows)
rows = [r for r in rows if norm(r[0]) not in obs]
print(f"excluidos observados: {before - len(rows)}", file=sys.stderr)

# dedupe exacto (conserva primera aparición: v2, luego v3 con scope, luego nuevo)
seen, uniq = set(), []
dups = 0
for r in rows:
    n = norm(r[0])
    if n in seen:
        dups += 1
        continue
    seen.add(n)
    uniq.append(r)
print(f"duplicados exactos eliminados: {dups}", file=sys.stderr)

with open(HERE / "pool.csv", "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f)
    w.writerow(["text", "label", "category", "family_id"])
    w.writerows(uniq)

from collections import Counter
print(f"pool: {len(uniq)}", dict(Counter(r[1] for r in uniq)), f"fams={len({r[3] for r in uniq})}", file=sys.stderr)
