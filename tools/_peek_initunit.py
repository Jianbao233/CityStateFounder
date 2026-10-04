import json, io, sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
apis = json.load(open(sys.argv[1], encoding='utf-8'))['apis']
for w in ['InitUnit','CreateUnit','GetUnits','IsAlive','GetCities','Create']:
    hits = [k for k in apis if w.lower() in k.lower()]
    print(f"  {w}: {hits[:8]}")
    for h in hits[:3]:
        print(f"      {h:28} -> {apis[h].get('c_func')}")