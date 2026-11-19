"""Generates Deckhand's textures into Art/ (32-bit TGA, power-of-two sizes).

    pip install pillow numpy
    python tools/gen_art.py              # write Art/*.tga
    python tools/gen_art.py mock.png     # also write a preview sheet

Everything is drawn at 4x and scaled down, so edges are smooth. Border, gem
and badge textures are grey on purpose: the addon tints them (rarity colour,
cost blue, attack orange, health red) with SetVertexColor.

The card occupies the top 256x358 of its 256x512 texture: use
SetTexCoord(0, 1, 0, 358/512).
"""
import pathlib
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

S = 4
CW, CH = 256, 358
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "Art"
rng = np.random.default_rng(7)


def sc(box):
    return [int(round(v * S)) for v in box]


def rmask(w, h, box, r):
    m = Image.new("L", (w * S, h * S), 0)
    x0, y0, x1, y1 = sc(box)
    ImageDraw.Draw(m).rounded_rectangle([x0, y0, x1 - 1, y1 - 1], int(r * S), fill=255)
    return m


def pmask(w, h, pts):
    m = Image.new("L", (w * S, h * S), 0)
    ImageDraw.Draw(m).polygon([(x * S, y * S) for x, y in pts], fill=255)
    return m


def minus(a, b):
    return ImageChops.multiply(a, ImageChops.invert(b))


def vgrad(w, h, top, bot, y0=0, y1=None):
    """Vertical gradient from `top` at y0 to `bot` at y1 (card pixels)."""
    y1 = h if y1 is None else y1
    t = ((np.arange(h * S) / S - y0) / max(1e-6, y1 - y0)).clip(0, 1)[:, None, None]
    a = np.array(top, "float32")[None, None, :] * (1 - t) + np.array(bot, "float32")[None, None, :] * t
    return Image.fromarray(np.broadcast_to(a, (h * S, w * S, 3)).astype("uint8"), "RGB")


def flat(w, h, col):
    return Image.new("RGB", (w * S, h * S), tuple(col))


def grain(rgb, amount, stretch=(1, 1), blur=0.0):
    w, h = rgb.size
    n = rng.normal(0, 1, (h // stretch[1] + 2, w // stretch[0] + 2)).clip(-2, 2)
    img = Image.fromarray((n * 60 + 128).astype("uint8"), "L").resize((w, h), Image.BICUBIC)
    if blur:
        img = img.filter(ImageFilter.GaussianBlur(blur * S))
    v = (np.asarray(img).astype("float32") - 128) / 120 * amount
    a = np.asarray(rgb).astype("float32") + v[:, :, None]
    return Image.fromarray(a.clip(0, 255).astype("uint8"), "RGB")


def new(w, h):
    return Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))


def put(dst, rgb, m):
    dst.paste(rgb, (0, 0), m)


def cut(dst, hole):
    dst.putalpha(minus(dst.getchannel("A"), hole))


def stroke(dst, w, h, box, r, col, width):
    outer = rmask(w, h, box, r)
    inner = rmask(w, h, [box[0] + width, box[1] + width, box[2] - width, box[3] - width], max(0, r - width))
    put(dst, flat(w, h, col), minus(outer, inner))


def finish(img, w, h, name, canvas=None):
    small = img.resize((w, h), Image.LANCZOS)
    cw, ch = canvas or (w, h)
    out = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    out.paste(small, (0, 0))
    OUT.mkdir(exist_ok=True)
    out.save(OUT / (name + ".tga"))
    return small


# ---------------------------------------------------------------------------
# Keep these in step with the layout numbers in UI/Widgets.lua.
ART = [16, 16, 240, 166]      # transparent window the icon shows through
NAME = [10, 158, 246, 214]    # two lines of name
TEXT = [16, 220, 240, 320]    # keywords and rules text


def card_base():
    img = new(CW, CH)
    body = grain(vgrad(CW, CH, (50, 41, 32), (24, 20, 16)), 7)
    put(img, body, rmask(CW, CH, [5, 5, CW - 5, CH - 5], 11))
    cut(img, rmask(CW, CH, ART, 4))
    stroke(img, CW, CH, [ART[0] - 2, ART[1] - 2, ART[2] + 2, ART[3] + 2], 6, (14, 11, 8), 2)
    # name banner, over the bottom edge of the art
    put(img, grain(vgrad(CW, CH, (86, 66, 40), (46, 35, 22), NAME[1], NAME[3]), 5), rmask(CW, CH, NAME, 3))
    stroke(img, CW, CH, NAME, 3, (168, 134, 66), 1.5)
    stroke(img, CW, CH, [NAME[0] + 1.5, NAME[1] + 1.5, NAME[2] - 1.5, NAME[3] - 1.5], 2, (30, 22, 14), 1)
    # rules box: parchment
    parch = grain(grain(vgrad(CW, CH, (222, 204, 166), (190, 168, 128), TEXT[1], TEXT[3]), 10, blur=3), 5)
    put(img, parch, rmask(CW, CH, TEXT, 5))
    stroke(img, CW, CH, TEXT, 5, (84, 64, 40), 1.5)
    stroke(img, CW, CH, [TEXT[0] + 1.5, TEXT[1] + 1.5, TEXT[2] - 1.5, TEXT[3] - 1.5], 4, (236, 222, 190), 1)
    return finish(img, CW, CH, "CardBase", (256, 512))


def card_border():
    img = new(CW, CH)
    full = [0, 0, CW, CH]
    stroke(img, CW, CH, full, 16, (22, 22, 22), 10)
    ring = minus(rmask(CW, CH, [1.5, 1.5, CW - 1.5, CH - 1.5], 14.5), rmask(CW, CH, [8.5, 8.5, CW - 8.5, CH - 8.5], 8))
    put(img, grain(vgrad(CW, CH, (255, 255, 255), (150, 150, 150)), 5), ring)
    stroke(img, CW, CH, [4, 4, CW - 4, CH - 4], 12, (120, 120, 120), 1.2)   # groove
    stroke(img, CW, CH, [2, 2, CW - 2, CH - 2], 14, (255, 255, 255), 1)     # highlight
    return finish(img, CW, CH, "CardBorder", (256, 512))


def anchor(d, cx, cy, col):
    def w(v):
        return int(v * S)
    d.ellipse(sc([cx - 8, cy - 40, cx + 8, cy - 24]), outline=col, width=w(4))
    d.line(sc([cx, cy - 24, cx, cy + 30]), fill=col, width=w(6))
    d.line(sc([cx - 16, cy - 12, cx + 16, cy - 12]), fill=col, width=w(5))
    d.arc(sc([cx - 28, cy - 22, cx + 28, cy + 32]), 12, 168, fill=col, width=w(6))
    for sx in (-1, 1):
        x = cx + sx * 28
        d.polygon([(w(x - sx * 9), w(cy + 2)), (w(x + sx * 5), w(cy + 4)), (w(x - sx * 1), w(cy + 17))], fill=col)


def card_back():
    img = new(CW, CH)
    full = [0, 0, CW, CH]
    put(img, flat(CW, CH, (20, 16, 10)), rmask(CW, CH, full, 16))
    gold = grain(vgrad(CW, CH, (226, 190, 100), (132, 98, 38)), 6)
    put(img, gold, rmask(CW, CH, [1.5, 1.5, CW - 1.5, CH - 1.5], 14.5))
    field_box = [10, 10, CW - 10, CH - 10]
    field = rmask(CW, CH, field_box, 8)
    put(img, grain(vgrad(CW, CH, (30, 44, 92), (12, 18, 44)), 5), field)
    lat = Image.new("L", (CW * S, CH * S), 0)
    d = ImageDraw.Draw(lat)
    for k in range(-CH, CW + CH, 24):
        d.line(sc([k, 0, k + CH, CH]), fill=255, width=int(1.3 * S))
        d.line(sc([k + CH, 0, k, CH]), fill=255, width=int(1.3 * S))
    put(img, flat(CW, CH, (46, 64, 124)), ImageChops.multiply(lat, field))
    stroke(img, CW, CH, field_box, 8, (16, 12, 8), 1.5)
    stroke(img, CW, CH, [20, 20, CW - 20, CH - 20], 5, (190, 154, 76), 1.5)
    cx, cy = CW // 2, CH // 2
    d = ImageDraw.Draw(img)
    d.ellipse(sc([cx - 62, cy - 62, cx + 62, cy + 62]), fill=(190, 154, 76, 255))
    d.ellipse(sc([cx - 58, cy - 58, cx + 58, cy + 58]), fill=(12, 18, 42, 255))
    d.ellipse(sc([cx - 53, cy - 53, cx + 53, cy + 53]), outline=(110, 88, 44, 255), width=int(1.2 * S))
    anchor(d, cx, cy, (222, 186, 98, 255))
    return finish(img, CW, CH, "CardBack", (256, 512))


def badge(name, pts=None):
    """A grey, tintable 64x64 badge: a circle, or the polygon `pts`."""
    n = 64
    img = new(n, n)
    if pts:
        outer = pmask(n, n, pts)
        inner = pmask(n, n, [(32 + (x - 32) * 0.84, 32 + (y - 32) * 0.84) for x, y in pts])
    else:
        outer, inner = Image.new("L", (n * S, n * S), 0), Image.new("L", (n * S, n * S), 0)
        ImageDraw.Draw(outer).ellipse(sc([3, 3, 61, 61]), fill=255)
        ImageDraw.Draw(inner).ellipse(sc([7, 7, 57, 57]), fill=255)
    put(img, flat(n, n, (20, 20, 20)), outer)
    yy, xx = np.mgrid[0:n * S, 0:n * S] / S
    dist = np.hypot(xx - 25, yy - 21)
    v = (255 - dist * 3.1).clip(120, 255)
    v[yy > 36 + (xx - 32) * 0.15] *= 0.86                  # a facet across the lower half
    face = Image.fromarray(np.repeat(v[:, :, None], 3, 2).astype("uint8"), "RGB")
    put(img, face, inner)
    return finish(img, n, n, name)


def star():
    """A grey, tintable five-pointed star (ladder stars)."""
    import math
    pts = []
    for i in range(10):
        r = 29 if i % 2 == 0 else 12.5
        a = -math.pi / 2 + i * math.pi / 5
        pts.append((32 + r * math.cos(a), 33.5 + r * math.sin(a)))
    return badge("Star", pts)


def board():
    n = 512
    base = flat(n, n, (60, 44, 29))
    base = grain(base, 16, stretch=(96 * S, 2 * S))
    base = grain(base, 9, stretch=(24 * S, 1 * S))
    base = grain(base, 4)
    img = base.convert("RGBA")
    d = ImageDraw.Draw(img)
    for y in range(0, n, 128):
        d.line(sc([0, y + 1, n, y + 1]), fill=(22, 15, 9, 255), width=2 * S)
        d.line(sc([0, y + 3, n, y + 3]), fill=(84, 63, 42, 255), width=S)
    return finish(img, n, n, "Board")


# ---------------------------------------------------------------------------
def tint(img, col):
    r, g, b, a = img.split()

    def f(ch, c):
        return ch.point(lambda v: v * c // 255)
    return Image.merge("RGBA", (f(r, col[0]), f(g, col[1]), f(b, col[2]), a))


def font(size, bold=True):
    for name in (("arialbd.ttf", "georgiab.ttf") if bold else ("arial.ttf",)):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def mock(path, parts):
    base, border, back, gem, hexa, shield, wood = parts
    rar = {"common": (204, 204, 204), "uncommon": (30, 255, 0), "rare": (51, 140, 255),
           "epic": (178, 76, 255), "legendary": (255, 128, 0)}
    cards = [("Loch Crocolisk", "common", 3, 2, 5, ""),
             ("Plainstrider", "uncommon", 2, 1, 3, "Arrive: restore\n2 Morale."),
             ("Booty Bay Bruiser", "rare", 4, 3, 5, "Guard, Sturdy"),
             ("Edwin VanCleef", "legendary", 4, 4, 3, "Swift, Stealth,\nPierce")]

    def card(name, rarity, cost, atk, hp, text):
        c = Image.new("RGBA", (CW + 24, CH + 24), (0, 0, 0, 0))
        art = vgrad(CW, CH, (70, 110, 120), (30, 50, 70)).resize((CW, CH)).convert("RGBA")
        ImageDraw.Draw(art).ellipse([78, 40, 178, 150], fill=(120, 160, 150, 255))
        c.paste(art.crop((ART[0], ART[1], ART[2], ART[3])), (12 + ART[0], 12 + ART[1]))
        c.alpha_composite(base, (12, 12))
        c.alpha_composite(tint(border, rar[rarity]), (12, 12))
        d = ImageDraw.Draw(c)
        d.text((12 + CW // 2, 12 + (NAME[1] + NAME[3]) // 2), name, font=font(19), fill=(250, 240, 215), anchor="mm",
               stroke_width=2, stroke_fill=(20, 14, 8))
        d.multiline_text((12 + CW // 2, 12 + (TEXT[1] + TEXT[3]) // 2), text, font=font(19, False), fill=(46, 34, 20),
                         anchor="mm", align="center")
        for img, col, pos, val in ((gem, (60, 120, 255), (0, 0), cost), (hexa, (255, 150, 40), (0, CH - 40), atk),
                                   (shield, (225, 50, 50), (CW - 40, CH - 40), hp)):
            c.alpha_composite(tint(img, col), pos)
            d.text((pos[0] + 32, pos[1] + 31), str(val), font=font(30), fill="white", anchor="mm",
                   stroke_width=3, stroke_fill=(10, 10, 10))
        return c

    big = [card(*c) for c in cards]
    bk = Image.new("RGBA", (CW + 24, CH + 24), (0, 0, 0, 0))
    bk.alpha_composite(back, (12, 12))
    big.append(bk)
    sheet = Image.new("RGBA", (len(big) * (CW + 30) + 6, CH + 24 + 170), (0, 0, 0, 255))
    for x in range(0, sheet.width, 512):
        for y in range(0, sheet.height, 512):
            sheet.paste(wood, (x, y))
    for i, c in enumerate(big):
        sheet.alpha_composite(c, (6 + i * (CW + 30), 4))
        small = c.resize((int(c.width * 90 / CW), int(c.height * 90 / CW)), Image.LANCZOS)   # in-game size
        sheet.alpha_composite(small, (6 + i * (CW + 30) + 80, CH + 32))
    sheet.save(path)


if __name__ == "__main__":
    parts = [card_base(), card_border(), card_back(), badge("Gem"),
             badge("BadgeAttack", [(32, 3), (58, 17), (58, 47), (32, 61), (6, 47), (6, 17)]),
             badge("BadgeHealth", [(7, 7), (57, 7), (57, 36), (32, 60), (7, 36)]), board()]
    star()
    print("wrote", ", ".join(sorted(p.name for p in OUT.glob("*.tga"))))
    if len(sys.argv) > 1:
        mock(sys.argv[1], parts)
        print("mock:", sys.argv[1])
