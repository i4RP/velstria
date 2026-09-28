#!/usr/bin/env python3
import json,csv,sys
from pathlib import Path
src=Path(sys.argv[1] if len(sys.argv)>1 else "data/json/velstria_master.json")
out=Path(sys.argv[2] if len(sys.argv)>2 else "reexport_csv"); out.mkdir(parents=True,exist_ok=True)
d=json.loads(src.read_text(encoding="utf-8"))
for name,rows in d.items():
    if not isinstance(rows,list) or not rows or not isinstance(rows[0],dict): continue
    keys=[]
    for r in rows:
        for k in r:
            if k not in keys: keys.append(k)
    with open(out/f"{name}.csv","w",encoding="utf-8-sig",newline="") as f:
        w=csv.DictWriter(f,fieldnames=keys); w.writeheader()
        for r in rows:
            w.writerow({k:(json.dumps(v,ensure_ascii=False) if isinstance(v,(list,dict)) else v) for k,v in r.items()})
print(out)
