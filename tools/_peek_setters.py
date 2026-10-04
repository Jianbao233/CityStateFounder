import json, io, sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
apis = json.load(open(sys.argv[1], encoding='utf-8'))['apis']
want = ['SetCivilizationTypeName','SetLeaderTypeName','GetLeaderTypeName','SetSlotStatus',
        'SetPlayerName','GetPlayerName','SetName','AddPlayer','UninitializePlayer',
        'InitializePlayer','SetPlayerLeader','SetRandomMinorStartingPosition']
for w in want:
    v = apis.get(w)
    if v is None:
        hits = [k for k in apis if w.lower() in k.lower()]
        print(f"  {w:30} 未命中；模糊: {hits[:5]}")
    else:
        print(f"  {w:30} -> {v.get('c_func')}  (lua={v.get('lua_name')})")