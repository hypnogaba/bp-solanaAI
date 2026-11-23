"""Makes worker/card.png, the picture X shows under a shared DZ Map post (1200 x 630).

  ~/Projects/forkbomb/.venv/bin/python tools/make_card.py
"""
import os, re
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open(os.path.join(ROOT, "main.lua")).read()
tiles = [tuple(map(int, m)) for m in re.findall(r"\{(\d+),(\d+)\}", src[src.index("local TILES = {"):src.index("-- Region of each tile")])]
groups = re.search(r'local TILE_REGION = "([a-m]+)"', src).group(1)
shark = re.findall(r'"([.bkwa]{20})"', src[src.index("local MAKO_BASE"):src.index("local function makoRows")])

W, H = 1200, 630
BG, LAND, ACCENT, PURPLE, TEXT, DIM = (0, 0, 0), (36, 36, 46), (20, 241, 149), (153, 69, 255), (255, 255, 255), (138, 138, 150)
SHADES = [PURPLE, (120, 60, 220), ACCENT, (90, 46, 153)]
img = Image.new("RGB", (W, H), BG)
world = Image.open(os.path.join(ROOT, "data/world.png")).convert("RGBA")
S = 6                                    # 160 x 74 -> 960 x 444
ox, oy = (W - 160 * S) // 2, 150
d = ImageDraw.Draw(img)
for y in range(74):
    for x in range(160):
        if world.getpixel((x, y))[3] == 0:
            continue
        t = next((i for i, (tx, ty) in enumerate(tiles) if tx == x // 8 and ty == y // 8), None)
        c = SHADES[(ord(groups[t]) - 97) % len(SHADES)] if t is not None else LAND
        d.rectangle([ox + x * S, oy + y * S, ox + x * S + S - 2, oy + y * S + S - 2], fill=c)
# the shark, bottom left, in the Pacific
SK = {"b": (25, 211, 245), "k": (0, 0, 0), "w": (255, 255, 255), "a": (20, 241, 149)}
for r, row in enumerate(shark):
    for c, ch in enumerate(row[::-1]):
        if ch in SK:
            d.rectangle([60 + c * 9, 470 + r * 9, 60 + c * 9 + 8, 470 + r * 9 + 8], fill=SK[ch])
font = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
big, small = ImageFont.truetype(font, 64), ImageFont.truetype(font, 30)
d.text((60, 40), "DZ MAP", font=big, fill=TEXT)
d.text((60, 112), "Light the world on DoubleZero fiber: 13 regions, 13 contributors", font=small, fill=DIM)
d.text((W - 60, H - 60), "Solana Breakpoint badge", font=small, fill=ACCENT, anchor="rs")
out = os.path.join(ROOT, "worker/card.png")
img.save(out, optimize=True)
print(out, os.path.getsize(out), "bytes")
