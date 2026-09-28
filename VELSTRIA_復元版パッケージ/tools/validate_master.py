#!/usr/bin/env python3
import json,sys
from pathlib import Path
p=Path(sys.argv[1] if len(sys.argv)>1 else "data/json/velstria_master.json")
d=json.loads(p.read_text(encoding="utf-8"))
errors=[]
def unique(rows,key):
    vals=[r[key] for r in rows]
    if len(vals)!=len(set(vals)): errors.append(f"duplicate {key}")
for rows,key in [(d["heroes"],"hero_id"),(d["skills"],"skill_id"),(d["equipment"],"item_id"),(d["store"],"sku"),(d["assets"],"asset_id"),(d["requirements"],"req_id")]:
    unique(rows,key)
hero_ids={x["hero_id"] for x in d["heroes"]}
for s in d["skills"]:
    if s["hero_id"] not in hero_ids: errors.append("orphan skill "+s["skill_id"])
for key,count in [("heroes",24),("skills",120),("equipment",72),("store",114),("assets",391),("requirements",110)]:
    if len(d[key])!=count: errors.append(f"{key} count")
print("PASS" if not errors else "FAIL")
for e in errors: print(e)
sys.exit(1 if errors else 0)
