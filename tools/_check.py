import sys, io
import xml.etree.ElementTree as ET
from collections import Counter

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

MAP_ROWS = [
    ("MAPSIZE_DUEL",     6,  9,  3),
    ("MAPSIZE_TINY",    10, 15,  6),
    ("MAPSIZE_SMALL",   14, 21,  9),
    ("MAPSIZE_STANDARD",18, 27, 12),
    ("MAPSIZE_LARGE",   22, 33, 15),
    ("MAPSIZE_HUGE",    24, 36, 18),
]
SCH = ["Domain", "MapSizeType", "Name", "Description", "MinPlayers", "MaxPlayers",
       "DefaultPlayers", "MinCityStates", "MaxCityStates", "DefaultCityStates", "SortIndex"]


def check_map_sizes(path):
    r = ET.parse(path).getroot()
    rows = list(r.iter("Replace"))
    print(f"  Replace 行数: {len(rows)}   按域: {dict(Counter(x.get('Domain') for x in rows))}")
    bad = []
    for x in rows:
        miss = [c for c in SCH if x.get(c) is None]
        extra = [k for k in x.keys() if k not in SCH]
        if miss or extra:
            bad.append((x.get("MapSizeType"), miss, extra))
    print("  列不完整:", bad or "无")
    for dom in ("StandardMapSizes", "ExtraStandardMapSizes"):
        print(f"  --- {dom} ---")
        for x in rows:
            if x.get("Domain") == dom:
                t = x.get("MapSizeType")
                off = dict((m[0], m[1]) for m in MAP_ROWS).get(t, "?")
                print(f"    {t:<20} 官方={off}  Max={x.get('MaxCityStates')}  Default={x.get('DefaultCityStates')}")


def check_count_range(path):
    r = ET.parse(path).getroot()
    rows = list(r.iter("Replace"))
    print(f"  Replace 行数: {len(rows)}")
    for x in rows:
        if x.get("QueryId") == "CityStateCountRange":
            print("  SQL 含 CASE 映射:", "CASE" in (x.get("SQL") or ""))
            print("  列:", list(x.keys()))


def check_modinfo(path):
    r = ET.parse(path).getroot()
    print("  FrontEndActions:")
    for a in r.find("FrontEndActions"):
        d = [f.text for f in a.findall("File")]
        lo = a.find("Properties/LoadOrder")
        print(f"    {a.tag:16} id={str(a.get('id')):26} LO={lo.text if lo is not None else '-':>8} {d}")
    print("  <Files> 相关:", [f.text for f in r.find("Files").findall("File")
                              if "MapSizes" in (f.text or "") or "CountRange" in (f.text or "")])


if __name__ == "__main__":
    mode, path = sys.argv[1], sys.argv[2]
    print(f"== {mode}: {path.split(chr(92))[-1]} ==")
    {"mapsizes": check_map_sizes, "range": check_count_range, "modinfo": check_modinfo}[mode](path)
