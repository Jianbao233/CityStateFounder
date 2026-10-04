import json, io, sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
d = json.load(open(sys.argv[1], encoding='utf-8'))
print("  顶层类型:", type(d).__name__)
if isinstance(d, dict):
    print("  键:", list(d.keys())[:8])
    for k in list(d.keys())[:3]:
        print(f"  {k} -> {type(d[k]).__name__}")
        if isinstance(d[k], list) and d[k]:
            print("    样例:", d[k][0] if not isinstance(d[k][0], dict) else list(d[k][0].items())[:4])