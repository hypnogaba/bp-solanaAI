# Regenerates data/world.png (160x74 land bitmap, equirectangular lon -170..180, lat 74..-58).
# pip install cartopy pillow ; python3 server/make_world.py
import cartopy.io.shapereader as shpreader
from shapely.geometry import Point
from shapely.prepared import prep
from shapely.ops import unary_union
from PIL import Image
W, H = 160, 74
LON0, LON1, LAT0, LAT1 = -170, 180, 74, -58
land = prep(unary_union([g for g in shpreader.Reader(shpreader.natural_earth('110m', 'physical', 'land')).geometries()]))
im = Image.new('RGBA', (W, H), (0, 0, 0, 0)); px = im.load()
for y in range(H):
    lat = LAT0 + (LAT1 - LAT0) * (y + 0.5) / H
    for x in range(W):
        lon = LON0 + (LON1 - LON0) * (x + 0.5) / W
        if land.contains(Point(lon, lat)): px[x, y] = (0x24, 0x24, 0x2E, 255)
im.quantize(colors=4, method=Image.Quantize.FASTOCTREE).save('data/world.png', optimize=True)
