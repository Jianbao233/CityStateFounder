import json, io, sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
apis = json.load(open(sys.argv[1], encoding='utf-8'))['apis']
print("=== 含 Turn 的 API（全部）===")
for k in sorted(apis):
    if 'turn' in k.lower():
        print(f"  {k:34} -> {apis[k].get('c_func')}")
print()
print("=== 含 End / Complete / Next / Pass 的 API ===")
for k in sorted(apis):
    kl = k.lower()
    if any(w in kl for w in ('endturn','completeturn','nextturn','passturn','doturn','advance')):
        print(f"  {k:34} -> {apis[k].get('c_func')}")
print()
print("=== 含 Process / Update 的 API ===")
for k in sorted(apis):
    kl = k.lower()
    if any(w in kl for w in ('processturn','updateturn','gameturn','turnprocess')):
        print(f"  {k:34} -> {apis[k].get('c_func')}")