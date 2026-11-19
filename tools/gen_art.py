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


def hues(h):
    """Hue (0..1, any shape) to RGB floats 0..1, full saturation."""
    h = (h % 1.0) * 6
    r = np.clip(np.abs(h - 3) - 1, 0, 1)
    g = np.clip(2 - np.abs(h - 2), 0, 1)
    b = np.clip(2 - np.abs(h - 4), 0, 1)
    return np.stack([r, g, b], -1)


def holo_foil():
    """Holographic foil for the art window, drawn with ADD blending: black is
    no change. 512x256 and periodic every 256 pixels across, so the addon
    shows a 256-wide window of it and slides that window to make it shimmer
    (Holo: SetTexCoord(u, u + 0.5, 0, 1), u from 0 to 0.5 and round again)."""
    w, h, period = 512, 256, 256
    r = np.random.default_rng(11)
    y, x = np.mgrid[0:h, 0:w].astype("float32")
    # rainbow bands on a diagonal, wobbling a little like real foil
    wob = 0.035 * np.sin(2 * np.pi * (y / h * 2 + x / period))
    band = (x / period * 2 + y / h * 0.8 + wob)
    rgb = hues(band) * 0.30 + 0.05
    # a bright sweep across, once per period
    d = ((x - y * 0.55) / period) % 1.0
    sweep = np.exp(-((d - 0.5) / 0.07) ** 2) * 0.45
    rgb = rgb + sweep[:, :, None] * (0.6 + 0.4 * hues(band + 0.33))
    # sparkles: the same random points in each period
    sp = np.zeros((h, period), "float32")
    for _ in range(70):
        cx, cy = r.uniform(0, period), r.uniform(0, h)
        s = r.uniform(0.6, 1.6)
        yy, xx = np.mgrid[0:h, 0:period].astype("float32")
        dx = np.minimum(np.abs(xx - cx), period - np.abs(xx - cx))
        sp += np.exp(-(dx ** 2 + (yy - cy) ** 2) / (2 * s * s)) * r.uniform(0.5, 1.0)
    sp = np.tile(sp, (1, w // period))
    rgb = rgb + np.clip(sp, 0, 1)[:, :, None] * 0.9
    img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype("uint8"), "RGB").convert("RGBA")
    OUT.mkdir(exist_ok=True)
    img.save(OUT / "Holo.tga")
    return img


def holo_ring():
    """A prismatic ring over the card's border (same layout as CardBorder),
    drawn with ADD blending on holographic cards."""
    img = new(CW, CH)
    ring = minus(rmask(CW, CH, [1.5, 1.5, CW - 1.5, CH - 1.5], 14.5), rmask(CW, CH, [8.5, 8.5, CW - 8.5, CH - 8.5], 8))
    y, x = np.mgrid[0:CH * S, 0:CW * S].astype("float32") / S
    rgb = hues((x + y) / 260.0) * 0.75 + 0.1
    put(img, Image.fromarray((np.clip(rgb, 0, 1) * 255).astype("uint8"), "RGB"), ring)
    return finish(img, CW, CH, "HoloRing", (256, 512))


# ---------------------------------------------------------------------------
# Rules diagrams (the Guide tab and the first-time keyword tips): a little
# board of three lanes, the enemy's row on top and yours below, with arrows
# for who strikes what. 256x128, shown at full size.
DW, DH = 256, 128
LANE_X = [48, 128, 208]           # lane centres
ROW_Y = {"them": 27, "you": 101}  # tile centres
TILE = (60, 40)
FOE = ((96, 34, 30), (190, 80, 66))     # fill, edge
OWN = ((30, 52, 96), (88, 136, 214))
GOLD = (255, 210, 90)
RED = (255, 90, 80)
GREEN = (110, 235, 110)
WHITE = (240, 236, 226)


class Diagram:
    def __init__(self):
        self.img = new(DW, DH)
        self.d = ImageDraw.Draw(self.img)
        put(self.img, flat(DW, DH, (22, 19, 15)), rmask(DW, DH, [1, 1, DW - 1, DH - 1], 8))
        stroke(self.img, DW, DH, [1, 1, DW - 1, DH - 1], 8, (98, 82, 54), 1.5)
        for x in (88, 168):
            self.d.line(sc([x, 8, x, DH - 8]), fill=(60, 52, 40, 255), width=S)

    def box(self, lane, row):
        cx, cy = LANE_X[lane - 1], ROW_Y[row]
        return [cx - TILE[0] / 2, cy - TILE[1] / 2, cx + TILE[0] / 2, cy + TILE[1] / 2]

    def text(self, xy, s, size, col, anchor="mm"):
        self.d.text((xy[0] * S, xy[1] * S), s, font=font(size * S), fill=col + (255,), anchor=anchor,
                    stroke_width=S, stroke_fill=(12, 10, 8, 255))

    def empty(self, lane, row):
        b = self.box(lane, row)
        self.d.rounded_rectangle(sc(b), 5 * S, outline=(78, 70, 58, 255), width=S)

    def unit(self, lane, row, stats, label=None, atk_col=None, hp_col=None, dead=False):
        fill, edge = OWN if row == "you" else FOE
        b = self.box(lane, row)
        self.d.rounded_rectangle(sc(b), 5 * S, fill=fill + (255,), outline=edge + (255,), width=int(1.5 * S))
        cx, cy = LANE_X[lane - 1], ROW_Y[row]
        if label:
            self.text((cx, b[1] + 8), label, 9, GOLD)
        atk, hp = stats.split("/")
        y = cy + (5 if label else 0)
        self.text((cx - 3, y), atk, 15, atk_col or WHITE, "rm")
        self.text((cx, y), "/", 15, (170, 160, 140), "mm")
        self.text((cx + 3, y), hp, 15, hp_col or WHITE, "lm")
        if dead:
            for a, c in (((b[0] + 8, b[1] + 6), (b[2] - 8, b[3] - 6)), ((b[0] + 8, b[3] - 6), (b[2] - 8, b[1] + 6))):
                self.d.line(sc([a[0], a[1], c[0], c[1]]), fill=RED + (255,), width=3 * S)

    def arrow(self, a, b, col, label=None, lpos=0.5, loff=(0, 0), size=9):
        import math
        (x0, y0), (x1, y1) = a, b
        ang = math.atan2(y1 - y0, x1 - x0)
        head = 8
        bx, by = x1 - math.cos(ang) * head * 0.8, y1 - math.sin(ang) * head * 0.8
        self.d.line(sc([x0, y0, bx, by]), fill=col + (255,), width=3 * S)
        pts = [(x1, y1),
               (x1 - math.cos(ang - 0.5) * head, y1 - math.sin(ang - 0.5) * head),
               (x1 - math.cos(ang + 0.5) * head, y1 - math.sin(ang + 0.5) * head)]
        self.d.polygon([(x * S, y * S) for x, y in pts], fill=col + (255,))
        if label:
            mx, my = x0 + (x1 - x0) * lpos + loff[0], y0 + (y1 - y0) * lpos + loff[1]
            self.text((mx, my), label, size, col)

    def save(self, key):
        return finish(self.img, DW, DH, "Diagram_" + key)


def top(lane):
    return (LANE_X[lane - 1], ROW_Y["them"] + TILE[1] / 2 + 1)


def bot(lane):
    return (LANE_X[lane - 1], ROW_Y["you"] - TILE[1] / 2 - 1)


def diagrams():
    out = []
    # lanes: open lane hits Morale, facing units fight, theirs gets through
    g = Diagram()
    g.unit(1, "you", "2/2")
    g.empty(1, "them")
    g.text((LANE_X[0], ROW_Y["them"]), "-2 Morale", 10, RED)
    g.arrow(bot(1), (LANE_X[0], ROW_Y["them"] + 9), GOLD)
    g.unit(2, "you", "2/3")
    g.unit(2, "them", "3/2")
    g.arrow((LANE_X[1] - 7, bot(2)[1]), (LANE_X[1] - 7, top(2)[1]), GOLD)
    g.arrow((LANE_X[1] + 7, top(2)[1]), (LANE_X[1] + 7, bot(2)[1]), RED)
    g.unit(3, "them", "1/2")
    g.empty(3, "you")
    g.text((LANE_X[2], ROW_Y["you"]), "-1 Morale", 10, RED)
    g.arrow(top(3), (LANE_X[2], ROW_Y["you"] - 9), RED)
    out.append(g.save("lanes"))

    g = Diagram()   # swift
    g.unit(2, "you", "3/2", "Swift")
    g.unit(2, "them", "2/2", dead=True)
    g.arrow(bot(2), top(2), GOLD, "first", loff=(22, 0), size=10)
    out.append(g.save("swift"))

    g = Diagram()   # guard
    g.unit(1, "them", "2/2")
    g.empty(1, "you")
    g.unit(2, "you", "3/6", "Guard")
    g.arrow((LANE_X[0] + 6, top(1)[1]), (LANE_X[1] - 26, ROW_Y["you"] - 14), RED, "2", loff=(-10, 4), size=11)
    g.empty(3, "them")
    g.empty(3, "you")
    out.append(g.save("guard"))

    g = Diagram()   # ranged
    g.unit(1, "you", "2/3", "Ranged")
    g.unit(2, "them", "3/4")
    g.unit(3, "them", "2/1", dead=True)
    g.text((LANE_X[2] + 6, ROW_Y["them"] + 36), "weakest", 10, GOLD)
    g.arrow((LANE_X[0] + 20, bot(1)[1]), (LANE_X[2] - 24, top(3)[1] + 4), GOLD)
    g.empty(1, "them")
    out.append(g.save("ranged"))

    g = Diagram()   # pierce
    g.unit(2, "you", "5/3", "Pierce")
    g.unit(2, "them", "2/2", dead=True)
    g.arrow(bot(2), top(2), GOLD, "5", loff=(10, 0), size=11)
    g.arrow((LANE_X[1] + 32, ROW_Y["them"]), (LANE_X[2] - 26, ROW_Y["them"]), RED)
    g.text((LANE_X[2] + 8, ROW_Y["them"]), "-3 Morale", 10, RED)
    out.append(g.save("pierce"))

    g = Diagram()   # cleave
    g.unit(2, "you", "3/5", "Cleave")
    for lane in (1, 2, 3):
        g.unit(lane, "them", "2/3")
    g.arrow(bot(2), top(2), GOLD)
    g.arrow((LANE_X[1] - 14, bot(2)[1]), (LANE_X[0] + 14, top(1)[1]), GOLD)
    g.arrow((LANE_X[1] + 14, bot(2)[1]), (LANE_X[2] - 14, top(3)[1]), GOLD)
    out.append(g.save("cleave"))

    g = Diagram()   # venom
    g.unit(2, "you", "1/3", "Venom")
    g.unit(2, "them", "6/6", dead=True)
    g.arrow(bot(2), top(2), GOLD, "1", loff=(10, 0), size=11)
    out.append(g.save("venom"))

    g = Diagram()   # drain
    g.unit(2, "you", "2/2", "Drain")
    g.unit(2, "them", "3/4", hp_col=RED)
    g.arrow(bot(2), top(2), GOLD, "2", loff=(10, 0), size=11)
    g.arrow((LANE_X[1] - 32, ROW_Y["you"]), (LANE_X[0] + 14, ROW_Y["you"]), GREEN)
    g.text((LANE_X[0] - 16, ROW_Y["you"]), "+2 Morale", 10, GREEN)
    out.append(g.save("drain"))

    g = Diagram()   # sturdy
    g.unit(2, "you", "2/1", "Sturdy", hp_col=GREEN)
    g.unit(2, "them", "5/5")
    g.arrow(top(2), bot(2), RED, "5", loff=(10, 0), size=11)
    g.text((LANE_X[2] - 4, ROW_Y["you"]), "survives", 10, GREEN)
    out.append(g.save("sturdy"))

    g = Diagram()   # regenerate
    g.unit(1, "you", "3/1", "Regen", hp_col=RED)
    g.unit(3, "you", "3/4", "Regen", hp_col=GREEN)
    g.arrow((LANE_X[0] + 34, ROW_Y["you"]), (LANE_X[2] - 34, ROW_Y["you"]), GREEN)
    g.text((LANE_X[1], ROW_Y["you"] - 30), "end of round", 10, GREEN)
    out.append(g.save("regen"))

    g = Diagram()   # rally
    g.unit(1, "you", "3/2", atk_col=GREEN)
    g.unit(2, "you", "3/3", "Rally")
    g.unit(3, "you", "3/2", atk_col=GREEN)
    g.arrow((LANE_X[1], ROW_Y["you"] - 24), (LANE_X[0] + 14, ROW_Y["you"] - 26), GREEN, "+1", loff=(0, -10), size=11)
    g.arrow((LANE_X[1], ROW_Y["you"] - 24), (LANE_X[2] - 14, ROW_Y["you"] - 26), GREEN, "+1", loff=(0, -10), size=11)
    out.append(g.save("rally"))

    g = Diagram()   # stealth
    b = g.box(2, "them")
    g.d.rounded_rectangle(sc(b), 5 * S, fill=(70, 40, 92, 255), outline=(176, 120, 230, 255), width=int(1.5 * S))
    g.text((LANE_X[1], ROW_Y["them"]), "Tactic", 11, WHITE)
    g.unit(2, "you", "4/3", "Stealth")
    g.arrow(top(2), (LANE_X[1], ROW_Y["you"] - 22), (176, 120, 230))
    cx, cy = LANE_X[1], 63
    for dx in (-1, 1):
        g.d.line(sc([cx - 9, cy - 9 * dx, cx + 9, cy + 9 * dx]), fill=RED + (255,), width=3 * S)
    g.text((LANE_X[2] + 2, 63), "can't target", 10, RED)
    out.append(g.save("stealth"))
    return out


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


# ---------------------------------------------------------------------------
# Combat effects (UI/Effects.lua). White on transparent: the addon tints them
# with SetVertexColor and draws most of them additively.
def _alpha_image(alpha, rgb=(255, 255, 255)):
    a = np.clip(alpha, 0, 1)
    img = np.zeros(a.shape + (4,), dtype=np.uint8)
    img[..., 0], img[..., 1], img[..., 2] = rgb
    img[..., 3] = (a * 255).round().astype(np.uint8)
    return Image.fromarray(img, "RGBA")


def _radius(n):
    y, x = np.mgrid[0:n, 0:n]
    c = (n - 1) / 2
    return np.sqrt((x - c) ** 2 + (y - c) ** 2) / c


def fx_spark():
    """A soft round glow with a hot centre: projectiles, trails, flashes."""
    r = _radius(64)
    a = np.exp(-(r ** 2) * 5.0) + 0.55 * np.clip(1 - r * 3.2, 0, 1) ** 2
    a = a * np.clip((1 - r) * 6, 0, 1)
    _alpha_image(a).save(OUT / "Spark.tga")


def fx_ring():
    """A soft ring: impact shockwaves."""
    r = _radius(128)
    a = np.exp(-((r - 0.78) / 0.075) ** 2) + 0.18 * np.exp(-((r - 0.6) / 0.2) ** 2)
    a = a * np.clip((1 - r) * 12, 0, 1)
    _alpha_image(a).save(OUT / "Ring.tga")


def fx_slash():
    """A tapered diagonal streak: melee impacts (mirrored for variety)."""
    n = 128
    m = Image.new("L", (n * S, n * S), 0)
    d = ImageDraw.Draw(m)
    pts_a, pts_b = [], []
    for i in range(41):
        t = i / 40
        x, y = 14 + t * 100, 114 - t * 100 + 18 * np.sin(np.pi * t)
        w = 9 * np.sin(np.pi * t) ** 0.8 + 0.6
        pts_a.append(((x - w * 0.7) * S, (y - w * 0.7) * S))
        pts_b.append(((x + w * 0.7) * S, (y + w * 0.7) * S))
    d.polygon(pts_a + pts_b[::-1], fill=255)
    glow = m.filter(ImageFilter.GaussianBlur(7 * S))
    core = m.filter(ImageFilter.GaussianBlur(1 * S))
    a = np.maximum(np.asarray(core, dtype=float) / 255, np.asarray(glow, dtype=float) / 255 * 0.9)
    small = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "L").resize((n, n), Image.LANCZOS)
    _alpha_image(np.asarray(small, dtype=float) / 255).save(OUT / "Slash.tga")


def _glyph(n, draw, name, blur=0.6):
    m = Image.new("L", (n * S, n * S), 0)
    draw(ImageDraw.Draw(m), n * S)
    m = m.filter(ImageFilter.GaussianBlur(blur * S)).resize((n, n), Image.LANCZOS)
    _alpha_image(np.asarray(m, dtype=float) / 255).save(OUT / (name + ".tga"))


def fx_skull():
    def draw(d, z):
        u = z / 64
        d.ellipse([12 * u, 6 * u, 52 * u, 44 * u], fill=255)
        d.rounded_rectangle([20 * u, 34 * u, 44 * u, 56 * u], 4 * u, fill=255)
        d.ellipse([19 * u, 20 * u, 30 * u, 33 * u], fill=0)
        d.ellipse([34 * u, 20 * u, 45 * u, 33 * u], fill=0)
        d.polygon([(32 * u, 33 * u), (28 * u, 41 * u), (36 * u, 41 * u)], fill=0)
        for x in (25, 30, 35):
            d.rectangle([x * u, 46 * u, (x + 2) * u, 56 * u], fill=0)
    _glyph(64, draw, "Skull")


def fx_shield():
    def draw(d, z):
        u = z / 64
        outer = [(32, 4), (56, 12), (54, 34), (32, 60), (10, 34), (8, 12)]
        inner = [(32, 10), (50, 16), (48, 33), (32, 53), (16, 33), (14, 16)]
        d.polygon([(x * u, y * u) for x, y in outer], fill=255)
        d.polygon([(x * u, y * u) for x, y in inner], fill=140)
        d.line([(32 * u, 12 * u), (32 * u, 50 * u)], fill=255, width=int(3 * u))
    _glyph(64, draw, "Shield")


def fx_frost():
    """Ice creeping in from the edges of a frozen card (a clear middle)."""
    n = 128
    r2 = np.random.default_rng(11)
    m = Image.new("L", (n * S, n * S), 0)
    d = ImageDraw.Draw(m)
    for _ in range(46):
        side = r2.integers(4)
        t = r2.uniform(0, n)
        x, y = [(t, 0), (n, t), (t, n), (0, t)][side]
        ang = [np.pi / 2, np.pi, -np.pi / 2, 0][side] + r2.uniform(-0.9, 0.9)
        length = r2.uniform(12, 34)
        x2, y2 = x + np.cos(ang) * length, y + np.sin(ang) * length
        d.line([(x * S, y * S), (x2 * S, y2 * S)], fill=255, width=int(1.6 * S))
        for k in (-1, 1):
            bx, by = x + (x2 - x) * 0.55, y + (y2 - y) * 0.55
            ba = ang + k * 0.7
            d.line([(bx * S, by * S), ((bx + np.cos(ba) * length * 0.35) * S, (by + np.sin(ba) * length * 0.35) * S)],
                   fill=220, width=int(1.1 * S))
    lines = np.asarray(m.filter(ImageFilter.GaussianBlur(0.7 * S)).resize((n, n), Image.LANCZOS), dtype=float) / 255
    y, x = np.mgrid[0:n, 0:n]
    edge = np.minimum(np.minimum(x, n - 1 - x), np.minimum(y, n - 1 - y)) / (n / 2)
    haze = np.clip(1 - edge * 2.6, 0, 1) ** 1.5 * 0.75 + 0.12
    a = np.clip(np.maximum(lines, haze), 0, 1)
    _alpha_image(a, (225, 242, 255)).save(OUT / "Frost.tga")


def fx_all():
    OUT.mkdir(exist_ok=True)
    fx_spark()
    fx_ring()
    fx_slash()
    fx_skull()
    fx_shield()
    fx_frost()



if __name__ == "__main__":
    parts = [card_base(), card_border(), card_back(), badge("Gem"),
             badge("BadgeAttack", [(32, 3), (58, 17), (58, 47), (32, 61), (6, 47), (6, 17)]),
             badge("BadgeHealth", [(7, 7), (57, 7), (57, 36), (32, 60), (7, 36)]), board()]
    star()
    holo_foil()
    holo_ring()
    dia = diagrams()
    fx_all()
    print("wrote", ", ".join(sorted(p.name for p in OUT.glob("*.tga"))))
    if len(sys.argv) > 1:
        mock(sys.argv[1], parts)
        print("mock:", sys.argv[1])
        sheet = Image.new("RGBA", (DW * 3 + 40, (DH + 10) * 4 + 10), (30, 26, 22, 255))
        for i, im in enumerate(dia):
            sheet.alpha_composite(im, (10 + (i % 3) * (DW + 10), 10 + (i // 3) * (DH + 10)))
        p = pathlib.Path(sys.argv[1])
        sheet.save(p.with_name(p.stem + "_diagrams.png"))
