"""The project logo for CurseForge and the like: a fan of three cards (a unit,
the card back with its anchor, a tactic) on card-table felt. No text, so it
reads at any size and doesn't depend on the project's name. All original:
the card frames are the addon's own (tools/gen_art.py), the pictures in
them are drawn here, not the game's icons.

    python tools/gen_logo.py            # media/logo.png (512) and media/logo-1024.png

It also draws the addon's own small icon (Art/Icon.tga: the addon list, the
window's title, the minimap button): just the card back on the felt, which
still reads at 16 pixels.
"""
import math
import pathlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

import gen_art as G

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "media"
N = 1024                       # drawn at this size, saved at N and N/2

# gen_art draws at 4x and shrinks into Art/; here we want the 4x pictures
# themselves, and nothing written to Art/.
G.finish = lambda img, w, h, name, canvas=None: img
S, K = G.S, 1.0                 # card pixels -> pixels of the 4x pictures: x S


def card_px(v):
    return v * S


def glyph_sword(d, box, col):
    x0, y0, x1, y1 = box
    cx, w, h = (x0 + x1) / 2, x1 - x0, y1 - y0
    blade = [(cx - w * 0.07, y0 + h * 0.62), (cx - w * 0.07, y0 + h * 0.2), (cx, y0 + h * 0.06),
             (cx + w * 0.07, y0 + h * 0.2), (cx + w * 0.07, y0 + h * 0.62)]
    d.polygon(blade, fill=col)
    d.rectangle([cx - w * 0.25, y0 + h * 0.62, cx + w * 0.25, y0 + h * 0.69], fill=col)
    d.rectangle([cx - w * 0.04, y0 + h * 0.69, cx + w * 0.04, y0 + h * 0.86], fill=col)
    d.ellipse([cx - w * 0.07, y0 + h * 0.84, cx + w * 0.07, y0 + h * 0.96], fill=col)


def glyph_star(d, box, col):
    x0, y0, x1, y1 = box
    cx, cy, r = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) * 0.42
    pts = []
    for i in range(16):
        rr = r if i % 2 == 0 else r * 0.38
        a = -math.pi / 2 + i * math.pi / 8
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    d.polygon(pts, fill=col)


def picture(kind):
    """What's in the card's icon hole: a sword for the unit, a burst of magic
    for the tactic, on a glow."""
    x0, y0, x1, y1 = [card_px(v) for v in G.ICON]
    w, h = int(x1 - x0), int(y1 - y0)
    yy, xx = np.mgrid[0:h, 0:w].astype("float32")
    t = np.clip(np.hypot(xx - w / 2, yy - h / 2) / (w * 0.7), 0, 1)
    inner, outer = ((255, 196, 96), (120, 40, 20)) if kind == "unit" else ((150, 210, 255), (40, 30, 120))
    rgb = np.array(inner, "float32") * (1 - t[:, :, None]) + np.array(outer, "float32") * t[:, :, None]
    img = Image.fromarray(rgb.astype("uint8"), "RGB").convert("RGBA")
    d = ImageDraw.Draw(img)
    box = (w * 0.12, h * 0.08, w * 0.88, h * 0.92)
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    (glyph_sword if kind == "unit" else glyph_star)(sd, box, (0, 0, 0, 150))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(w * 0.03)), (int(w * 0.02), int(h * 0.03)))
    (glyph_sword if kind == "unit" else glyph_star)(d, box, (255, 250, 236, 255) if kind == "unit" else (255, 255, 255, 255))
    return img, (int(x0), int(y0))


def bars(d, box, col, rows, widths):
    """Stand-ins for lines of text (unreadable at a logo's size anyway)."""
    x0, y0, x1, y1 = [card_px(v) for v in box]
    lh = (y1 - y0) / (rows + 1)
    for i, wf in enumerate(widths[:rows]):
        cy = y0 + lh * (i + 1)
        half = (x1 - x0) * wf / 2
        cx = (x0 + x1) / 2
        d.rounded_rectangle([cx - half, cy - lh * 0.16, cx + half, cy + lh * 0.16], lh * 0.16, fill=col)


def face(kind, rarity, stats):
    body = G.card_body(kind)
    img = Image.new("RGBA", body.size, (0, 0, 0, 0))
    pic, pos = picture(kind)
    img.alpha_composite(pic, pos)
    img.alpha_composite(body)
    img.alpha_composite(G.tint(G.card_rim(), G.RIM[rarity]))
    d = ImageDraw.Draw(img)
    bars(d, G.NAME, (250, 240, 214, 255), 1, [0.62])
    bars(d, G.TYPE, (255, 236, 196, 200) if kind == "unit" else (232, 234, 255, 200), 1, [0.36])
    t = G.TEXT[kind]
    text_box = [t[0], t[1], t[2], t[3] - (24 if kind == "unit" else 4)]
    bars(d, text_box, (70, 52, 32, 200) if kind == "unit" else (50, 44, 90, 200), 3, [0.72, 0.8, 0.5])
    k = 256 / 112                                     # UI units -> card pixels

    def put_jewel(j, cx, cy, size, tint=None):
        j = j.resize((int(card_px(size * k)), int(card_px(size * k))), Image.LANCZOS)
        if tint:
            j = G.tint(j, tint)
        img.alpha_composite(j, (int(card_px(cx * k) - j.width / 2), int(card_px(cy * k) - j.height / 2)))
        return card_px(cx * k), card_px(cy * k)
    gem = G.jewel("RarityGem", "diamond", (240, 240, 240), rim=(200, 200, 200), facets=4)
    put_jewel(gem, 56, G.GEM_Y[kind] / k, 13, G.RARITY[rarity])
    f = G.mock_font(card_px(16 * k))
    for (j, cx, cy, val) in stats:
        x, y = put_jewel(j, cx, cy, 30)
        d.text((x, y - card_px(0.5 * k)), str(val), font=f, fill="white", anchor="mm",
               stroke_width=int(card_px(1.2 * k)), stroke_fill=(10, 10, 10))
    return img


def logo():
    cost = G.jewel("StatCost", "circle", (52, 112, 236), facets=8)
    atk = G.jewel("StatAttack", "hex", (236, 162, 42))
    hp = G.jewel("StatHealth", "shield", (214, 44, 40))
    unit = face("unit", "legendary", [(cost, 14, 14, 3), (atk, 15, 140, 4), (hp, 97, 140, 5)])
    tactic = face("tactic", "epic", [(cost, 14, 14, 2)])
    back = G.card_back()

    # the field: green card-table felt, lighter in the middle, and a gold edge
    yy, xx = np.mgrid[0:N, 0:N].astype("float32")
    t = np.clip(np.hypot(xx - N / 2, yy - N * 0.47) / (N * 0.72), 0, 1) ** 1.2
    rgb = np.array((40, 112, 72), "float32") * (1 - t[:, :, None]) + np.array((5, 24, 14), "float32") * t[:, :, None]
    felt = np.random.default_rng(3).normal(0, 1, (N, N)).astype("float32")
    rgb = rgb * (1 + felt[:, :, None] * 0.035)
    img = Image.fromarray(np.clip(rgb, 0, 255).astype("uint8"), "RGB").convert("RGBA")
    glow = Image.new("L", (N, N), 0)
    ImageDraw.Draw(glow).ellipse([N * 0.18, N * 0.16, N * 0.82, N * 0.8], fill=150)
    glow = glow.filter(ImageFilter.GaussianBlur(N * 0.09))
    gold = Image.new("RGBA", (N, N), (255, 196, 90, 0))
    gold.putalpha(glow)
    img.alpha_composite(gold)

    # the three cards: a tactic and a unit fanned behind the card back
    ch = int(N * 0.64)
    cw = int(ch * G.CW / G.CH)

    def place(card, angle, cx, cy, scale=1.0):
        c = card.resize((int(cw * scale), int(ch * scale)), Image.LANCZOS).rotate(angle, Image.BICUBIC, expand=True)
        sh = Image.new("RGBA", c.size, (0, 0, 0, 0))
        sh.putalpha(c.getchannel("A").point(lambda v: v * 0.6))
        sh = sh.filter(ImageFilter.GaussianBlur(N * 0.018))
        img.alpha_composite(sh, (int(cx - c.width / 2 + N * 0.012), int(cy - c.height / 2 + N * 0.022)))
        img.alpha_composite(c, (int(cx - c.width / 2), int(cy - c.height / 2)))
    place(tactic, -21, N * 0.685, N * 0.54, 0.86)
    place(unit, 21, N * 0.315, N * 0.54, 0.86)
    place(back, 0, N * 0.5, N * 0.48, 0.96)

    # a thin gold edge, inset so a rounded crop doesn't cut it off
    edge = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle([N * 0.025, N * 0.025, N * 0.975, N * 0.975], N * 0.08,
                                           outline=(214, 172, 84, 255), width=int(N * 0.008))
    img.alpha_composite(edge)
    return img.convert("RGB")


def felt(n):
    yy, xx = np.mgrid[0:n, 0:n].astype("float32")
    t = np.clip(np.hypot(xx - n / 2, yy - n * 0.47) / (n * 0.72), 0, 1) ** 1.2
    rgb = np.array((40, 112, 72), "float32") * (1 - t[:, :, None]) + np.array((5, 24, 14), "float32") * t[:, :, None]
    return Image.fromarray(np.clip(rgb, 0, 255).astype("uint8"), "RGB").convert("RGBA")


def icon():
    n = 256
    img = felt(n)
    back = G.card_back()
    ch = int(n * 0.86)
    c = back.resize((int(ch * G.CW / G.CH), ch), Image.LANCZOS)
    sh = Image.new("RGBA", c.size, (0, 0, 0, 0))
    sh.putalpha(c.getchannel("A").point(lambda v: v * 0.6))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(6)), ((n - c.width) // 2 + 4, (n - c.height) // 2 + 6))
    img.alpha_composite(c, ((n - c.width) // 2, (n - c.height) // 2))
    small = img.convert("RGB").resize((64, 64), Image.LANCZOS).convert("RGBA")
    small.save(ROOT / "Art" / "Icon.tga")
    return small


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    im = logo()
    im.save(OUT / "logo-1024.png")
    im.resize((N // 2, N // 2), Image.LANCZOS).save(OUT / "logo.png")
    icon()
    print("wrote", ", ".join(p.name for p in sorted(OUT.glob("logo*.png"))), "and Art/Icon.tga")
