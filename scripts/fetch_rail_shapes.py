#!/usr/bin/env python3
"""Builds Thailand/Models/BangkokRailShapes.json: the track geometry of each line in
BangkokRail.json, from OpenStreetMap route relations (one direction per line), joined into
continuous polylines and simplified (~4 m tolerance) so the bundled file stays small.

Run again to refresh:  python3 scripts/fetch_rail_shapes.py
"""
import json, math, pathlib, time, urllib.parse, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "Thailand/Models/BangkokRailShapes.json"
SERVERS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]

# app line id -> OSM route relation id (one direction is enough for the map)
RELATIONS = {
    "bts-sukhumvit": 444651,
    "bts-silom": 2067854,
    "bts-gold": 11681439,
    "mrt-blue": 444659,
    "mrt-purple": 6988563,
    "mrt-yellow": 15806897,
    "mrt-pink": 16740886,
    "arl": 2148241,
    "srt-dark-red": 13058384,
}

def overpass(query):
    """POST to Overpass, trying each server a few times."""
    data = urllib.parse.urlencode({"data": query}).encode()
    for server in SERVERS * 3:
        try:
            req = urllib.request.Request(server, data=data, headers={"User-Agent": "WanderHub/1.0 (build script)"})
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.load(r)
        except Exception as e:
            print("  retrying:", e)
            time.sleep(10)
    raise SystemExit("Overpass unavailable")

CACHE = pathlib.Path("/tmp/wanderhub-rail-shapes")

def track_ways(rel_id):
    """Track ways of a route relation, with geometry (railway=* only: skips platforms)."""
    CACHE.mkdir(exist_ok=True)
    cached = CACHE / f"{rel_id}.json"
    if cached.exists():
        return json.loads(cached.read_text())
    d = overpass(f'[out:json][timeout:90];relation({rel_id});way(r)["railway"];out geom;')
    ways = [[(p["lat"], p["lon"]) for p in e["geometry"]] for e in d["elements"] if "geometry" in e]
    cached.write_text(json.dumps(ways))
    return ways

def chain(ways):
    """Merges ways that share endpoints (in any order) into as few continuous lines as possible."""
    lines = [list(map(tuple, w)) for w in ways if len(w) >= 2]
    merged = True
    while merged:
        merged = False
        for i in range(len(lines)):
            for j in range(i + 1, len(lines)):
                a, b = lines[i], lines[j]
                if a[-1] == b[0]: joined = a + b[1:]
                elif a[-1] == b[-1]: joined = a + b[::-1][1:]
                elif a[0] == b[-1]: joined = b + a[1:]
                elif a[0] == b[0]: joined = b[::-1] + a[1:]
                else: continue
                lines[i] = joined
                del lines[j]
                merged = True
                break
            if merged:
                break
    return lines

def perp(p, a, b):
    # meters, equirectangular is fine at this scale
    k = 111_320
    ax, ay = a[1] * k * math.cos(math.radians(a[0])), a[0] * k
    bx, by = b[1] * k * math.cos(math.radians(b[0])), b[0] * k
    px, py = p[1] * k * math.cos(math.radians(p[0])), p[0] * k
    dx, dy = bx - ax, by - ay
    if dx == dy == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))

def simplify(points, tol=4.0):
    if len(points) < 3:
        return points
    dmax, idx = 0, 0
    for i in range(1, len(points) - 1):
        d = perp(points[i], points[0], points[-1])
        if d > dmax:
            dmax, idx = d, i
    if dmax > tol:
        return simplify(points[: idx + 1], tol)[:-1] + simplify(points[idx:], tol)
    return [points[0], points[-1]]

shapes = {}
for line_id, rel in RELATIONS.items():
    print(f"{line_id}: relation {rel}")
    lines = [simplify(l) for l in chain(track_ways(rel))]
    lines = [[[round(lat, 5), round(lon, 5)] for lat, lon in l] for l in lines if len(l) >= 2]
    shapes[line_id] = lines
    print(f"  {len(lines)} segment(s), {sum(len(l) for l in lines)} points")
    time.sleep(1)

OUT.write_text(json.dumps({"source": "OpenStreetMap contributors (ODbL), fetched " + time.strftime("%Y-%m"),
                           "shapes": shapes}, separators=(",", ":")))
print("wrote", OUT, f"{OUT.stat().st_size // 1024} KB")
