"""Berlin's park benches, picnic tables and water playgrounds — built with RustGIS.

Usage: python make_bench_map.py <data_dir> <out_dir>
  data_dir must contain:
    repos/Berlin-Geodaten/berlin_bezirke.geojson                 (districts, Amt für Statistik BB, CC-BY)
    green/technologiestiftung_erfrischungskarte/POIs/2026/pois_jul2026_v2.geojson
        (ODIS Erfrischungskarte points: benches & picnic tables from OpenStreetMap, ODbL;
         water playgrounds from Berlin open data)
"""
import sys, json, collections, rustgis

base, out = sys.argv[1], sys.argv[2]
BEZ = f"{base}/repos/Berlin-Geodaten/berlin_bezirke.geojson"
POIS = f"{base}/green/technologiestiftung_erfrischungskarte/POIs/2026/pois_jul2026_v2.geojson"

# ---- palette & type -------------------------------------------------------
BG = "#F4EEE2"         # warm paper
LAND = "#FBF8F2"
LAND_EDGE = "#D9CFBC"
INK = "#1F2B24"
MUTED = "#6E7469"
BENCH = "#2F6B47"      # park green
PICNIC = "#EE6A4C"     # coral
SPLASH = "#2C9AD8"     # water blue
TITLE_FONT, BODY_FONT = "Poppins", "Inter"

PW, PH = 420, 297
SCALE = 160000
CTR = (13.306, 52.500)

# ---- split the ODIS points by category -----------------------------------
by = collections.defaultdict(list)
for f in json.load(open(POIS))["features"]:
    by[f["properties"]["category"]].append(
        {"type": "Feature", "geometry": f["geometry"], "properties": {}})
N_BENCH, N_PICNIC, N_SPLASH = len(by["Sitzbank"]), len(by["Picknicktisch"]), len(by["Wasserspielplatz"])
print("benches", N_BENCH, "picnic", N_PICNIC, "splash", N_SPLASH)

def fc(features):
    return json.dumps({"type": "FeatureCollection", "features": features})

def feat(geom, **props):
    return {"type": "Feature", "geometry": geom, "properties": props}

# ---- annotations (target, label anchor, headline, body) -------------------
NOTES = [
    ((13.3500, 52.5145), (13.245, 52.566), "Tiergarten",
     "Berlin's living room: about 800|benches in and around it"),
    ((13.4010, 52.4740), (13.325, 52.408), "Tempelhofer Feld",
     "The old airfield is mostly open sky.|Bring a blanket."),
]

def leader_end(t, a):
    return [a[0], a[1] + 0.0140] if t[1] > a[1] else [a[0], a[1] - 0.0195]

bg = fc([feat({"type": "Polygon", "coordinates": [[[11.5, 51.6], [15.3, 51.6], [15.3, 53.4],
                                                     [11.5, 53.4], [11.5, 51.6]]]})])
leaders = fc([feat({"type": "LineString", "coordinates": [list(t), leader_end(t, a)]})
              for t, a, _, _ in NOTES])
targets = fc([feat({"type": "Point", "coordinates": list(t)}) for t, _, _, _ in NOTES])
heads = fc([feat({"type": "Point", "coordinates": [a[0], a[1] + 0.0048]}, t=h) for _, a, h, _ in NOTES])
bodies = fc([feat({"type": "Point", "coordinates": list(a)}, t=b) for _, a, _, b in NOTES])

s = rustgis.Session(data=[BEZ])
B = "berlin_bezirke"
for name, txt in [("bg", bg), ("benches", fc(by["Sitzbank"])), ("picnic", fc(by["Picknicktisch"])),
                  ("splash", fc(by["Wasserspielplatz"])), ("parks", fc(by["Gruenanlage"])),
                  ("leaders", leaders), ("targets", targets),
                  ("heads", heads), ("bodies", bodies)]:
    s.run("layer.addDataText", fileName=f"{name}.geojson", text=txt, name=name)

# ---- map styling ----------------------------------------------------------
s.run("map.basemap", name="blank")
s.run("layer.color", layer="bg", color=BG + "FF")
s.run("layer.outline", layer="bg", color=BG + "00", width=0)

s.run("layer.color", layer=B, color=LAND + "FF")
s.run("layer.outline", layer=B, color=LAND_EDGE, width=0.9)
s.run("labels.enable", layer=B, on=True)
s.run("labels.field", layer=B, field="name")
s.run("labels.style", layer=B, size=10, color="#A39A88", font=BODY_FONT, halo=True,
      haloColor=LAND, haloWidth=1.4, spacing=1.2, wrapChar="-")

def dots(layer, color, size, outline=None, width=0):
    s.run("layer.marker", layer=layer, shape="circle", size=size)
    s.run("layer.color", layer=layer, color=color)
    s.run("layer.outline", layer=layer, color=outline or "#00000000", width=width)

dots("parks", "#7FB685" + "38", 11)
dots("benches", BENCH + "C8", 2.2)
dots("picnic", PICNIC + "FF", 3.2, outline=LAND, width=0.6)
dots("splash", SPLASH + "FF", 6.0, outline="#FFFFFF", width=1.4)

s.run("layer.outline", layer="leaders", color=INK + "99", width=0.6)
dots("targets", "#00000000", 9, outline=INK, width=1.1)
for lyr, size, col, bold in [("heads", 13.5, INK, True), ("bodies", 11, MUTED, False)]:
    dots(lyr, "#00000000", 0.1)
    s.run("labels.enable", layer=lyr, on=True)
    s.run("labels.field", layer=lyr, field="t")
    s.run("labels.style", layer=lyr, size=size, color=col, bold=bold, font=BODY_FONT,
          halo=True, haloColor=BG, haloWidth=2.2, wrapChar="|", lineAlign="center")
    s.run("labels.placement", layer=lyr, position="below" if lyr == "bodies" else "center",
          showAll=True)

order = ["heads", "bodies", "targets", "leaders", "splash", "picnic", "benches", "parks", B, "bg"]
for i, lyr in enumerate(order):
    if s.layer_names().index(lyr) != i:
        s.run("layer.move", layer=lyr, to=i)
s.run("map.projection", type="EPSG:25833")

# ---- layout ---------------------------------------------------------------
s.run("layout.new", name="Benches", width=PW, height=PH, template="blank")
fr = s.run("layout.addFrame", x=0, y=0, w=PW, h=PH)["element"]
s.run("layout.update", element=fr, center=list(CTR), scale=SCALE)

def text(t, x, y, w, h, size, color=INK, font=BODY_FONT, bold=False, **kw):
    s.run("layout.addElement", kind="text", text=t, x=x, y=y, w=w, h=h, size=size,
          color=color, font=font, bold=bold, **kw)

L = 22
text("BERLIN  ·  PARKS & PLAYGROUNDS", L, 18, 180, 10, 14, color=BENCH, font=TITLE_FONT,
     bold=True, letterSpacing=3)
text(f"{N_BENCH:,} places\nto sit down", L, 31, 180, 50, 35, font=TITLE_FONT, bold=True)
text("Every green dot is a public bench, every\n"
     "soft halo a public green space. Where\n"
     "benches crowd there is a park, a lakeside\n"
     "path or a leafy square: Berlin, drawn by\n"
     "the places people stop, sit and watch\n"
     "the city go by.",
     L, 84, 112, 42, 13.5, color=MUTED)

# hand-built key
ky = 134
def key_dot(y, color, d, outline=None):
    s.run("layout.addElement", kind="circle", x=L + 5 - d / 2, y=y + 3.2 - d / 2, w=d, h=d,
          fill=color + "FF", outline=outline or color, width=0.8 if outline else 0)
key_dot(ky, BENCH, 2.4)
text(f"Park bench  ({N_BENCH:,})", L + 14, ky, 100, 7, 12, color=INK)
key_dot(ky + 10, PICNIC, 3.2, outline="#FFFFFF")
text(f"Picnic table  ({N_PICNIC:,})", L + 14, ky + 10, 100, 7, 12, color=INK)
key_dot(ky + 20, SPLASH, 5.0, outline="#FFFFFF")
text(f"Water playground  ({N_SPLASH})", L + 14, ky + 20, 100, 7, 12, color=INK)
text("Splash pads and paddling pools,\nopen on hot summer days.", L + 14, ky + 27.5, 100, 12, 11,
     color=MUTED)
key_dot(ky + 43, "#7FB685", 7.0)
text("Public green space", L + 14, ky + 43, 100, 7, 12, color=INK)

s.run("layout.addElement", kind="scaleBar", units="kilometers", divisions=2, style="line",
      color=MUTED, x=L, y=252, w=40, h=9)
s.run("layout.addElement", kind="northArrow", style="compass", x=L + 50, y=242, w=16, h=20)
text("ETRS89 / UTM zone 33N\nEPSG:25833", L + 72, 249, 60, 12, 10, color=MUTED)
text("Data: benches & picnic tables © OpenStreetMap contributors (ODbL); water playgrounds: Land Berlin;\n"
     "both via ODIS Erfrischungskarte (Jul 2026). Districts: Amt für Statistik Berlin-Brandenburg, CC-BY.\n"
     "Graphic: Klaus Wiese  |  Made with RustGIS " + rustgis.__version__,
     L, 266, 300, 20, 9.5, color=MUTED)

s.run("layout.export", path=f"{out}/berlin_benches_rustgis.png", dpi=200)
s.run("layout.export", path=f"{out}/berlin_benches_rustgis.pdf", allPages=False)
s.save(f"{out}/berlin_benches.rgis")
for n, err in s.notices():
    if err:
        print("ERR", n)
