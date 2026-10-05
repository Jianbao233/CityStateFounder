import json, io, sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
apis = json.load(open(sys.argv[1], encoding='utf-8'))['apis']
print("  含 Operation 的 API:")
for k in sorted(apis):
    if 'operation' in k.lower():
        print(f"    {k:42} -> {apis[k].get('c_func')}")