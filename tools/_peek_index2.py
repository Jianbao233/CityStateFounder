import json, io, sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
d = json.load(open(sys.argv[1], encoding='utf-8'))
apis = d['apis']
print("  API 数:", len(apis))
want = ['IsAlive','GetColor','SetColor','SetAlive','GetSlotStatus','SetPlayerSlotStatus',
        'GetCivilizationTypeName','GetPlayerColorValues','GetDiplomacy','IsMajor']
for w in want:
    v = apis.get(w)
    if v is None:
        # 模糊找
        hits = [k for k in apis if w.lower() in k.lower()]
        print(f"  {w:26} 未精确命中；模糊: {hits[:4]}")
    else:
        print(f"  {w:26} -> {v}")