"""Generates Tradewinds's textures into Art/ (32-bit TGA, power-of-two sizes).

    pip install pillow numpy
    python tools/gen_art.py              # write Art/*.tga
    python tools/gen_art.py mock.png     # also write a preview sheet of cards

Everything is drawn at 4x and scaled down, so edges are smooth. The card's
rim, the rarity gem and the star are grey on purpose: the addon tints them
with SetVertexColor. The stat badges and the card bodies are in full colour.

The card occupies the top 256x357 of its 256x512 texture: use
SetTexCoord(0, 1, 0, 357/512).
"""
import math
import os
import pathlib
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

S = 4
CW, CH = 256, 357
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
# The card face. Keep these in step with the layout numbers in UI/Widgets.lua.
# Card pixels: the card is 256 x 357 at the top of a 256 x 512 texture and is
# 112 x 156 on screen (UI.CARD_W, UI.CARD_H).
#
# Four layers, back to front: the icon (through its hole), the body (CardUnit
# or CardTactic: everything but the rim, the picture's glow and the icon's
# frame included), the rim (CardRim, grey, tinted by rarity), then the gems
# and the text.
ART = [14, 14, 242, 146]       # the picture: a glow in the body's colours
ICON = [78, 25, 178, 125]      # the icon, whole and square, framed in its middle
NAME = [8, 136, 248, 170]      # name banner, over the art's bottom edge
TYPE = [20, 170, 236, 195]     # type line: "Beast unit", "Tactic: enemy lane"
TEXT = {"unit": [16, 199, 240, 310], "tactic": [16, 199, 240, 332]}   # rules box
GEM_Y = {"unit": 333, "tactic": 342}                                  # rarity gem
GLOW_PAD = 22                  # CardGlow: the card plus this much on every side

# Units: warm wood and bronze, parchment. Tactics: deep indigo and silver,
# cool vellum. The shapes are the same on both, in the body's own colours.
PAL = {
    "unit": dict(
        body=((70, 54, 40), (34, 26, 19)), edge=(206, 168, 100), edge2=(120, 88, 46),
        banner=((54, 42, 31), (26, 20, 14)), plate=((112, 84, 48), (70, 51, 28)),
        box=((240, 230, 204), (218, 202, 166)), boxedge=(108, 80, 46), shade=(90, 66, 40),
        glow=(132, 96, 58), dark=(26, 19, 13)),
    "tactic": dict(
        body=((52, 50, 98), (22, 20, 50)), edge=(176, 190, 236), edge2=(88, 92, 150),
        banner=((44, 38, 86), (20, 17, 44)), plate=((84, 70, 156), (50, 41, 104)),
        box=((232, 232, 244), (206, 204, 228)), boxedge=(86, 80, 140), shade=(60, 56, 110),
        glow=(90, 82, 180), dark=(15, 13, 38)),
}


def grow(box, d):
    return [box[0] - d, box[1] - d, box[2] + d, box[3] + d]


def window(kind, box):
    return rmask(CW, CH, box, 6)


def inner_shadow(hole, px, strength):
    """A darkening just inside the edge of `hole` (an L mask at S scale)."""
    blur = ImageChops.invert(hole).filter(ImageFilter.GaussianBlur(px * S))
    a = np.asarray(blur, "float32") / 255 * np.asarray(hole, "float32") / 255
    a = np.clip(a * 2.0, 0, 1) * strength
    return Image.fromarray((a * 255).astype("uint8"), "L")


def overlay(img, rgb, alpha):
    layer = Image.new("RGBA", img.size, tuple(rgb) + (0,))
    layer.putalpha(alpha)
    return Image.alpha_composite(img, layer)


def backdrop(kind):
    """The picture behind the icon: a soft glow from the middle, in the
    body's colours (rays of light on a tactic)."""
    p = PAL[kind]
    yy, xx = np.mgrid[0:CH * S, 0:CW * S].astype("float32") / S
    cx, cy = (ICON[0] + ICON[2]) / 2, (ICON[1] + ICON[3]) / 2
    t = np.clip(np.hypot((xx - cx) / 1.3, yy - cy) / 105, 0, 1) ** 0.85
    glow, dark = np.array(p["glow"], "float32"), np.array(p["dark"], "float32")
    rgb = glow[None, None, :] * (1 - t[:, :, None]) + dark[None, None, :] * t[:, :, None]
    if kind == "tactic":
        rays = (np.cos(np.arctan2(yy - cy, xx - cx) * 14) * 0.5 + 0.5) ** 5 * (1 - t) * 26
        rgb = rgb + rays[:, :, None] * np.array([0.75, 0.75, 1.0], "float32")[None, None, :]
    return grain(Image.fromarray(np.clip(rgb, 0, 255).astype("uint8"), "RGB"), 5)


def card_body(kind):
    p = PAL[kind]
    img = new(CW, CH)
    body = vgrad(CW, CH, *p["body"])
    body = grain(grain(body, 7, stretch=(1, 18 * S)), 3) if kind == "unit" else grain(grain(body, 5, blur=6), 3)
    put(img, body, rmask(CW, CH, [3, 3, CW - 3, CH - 3], 13))
    if kind == "tactic":   # faint arcane circles behind the panels
        d = ImageDraw.Draw(img)
        for r, wdt in ((150, 1.2), (128, 0.8)):
            cx, cy = CW / 2, 250
            d.ellipse([(cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S], outline=(84, 82, 150, 255),
                      width=int(wdt * S))
    # the picture: a metal edge, a dark line, the glow, shaded at its edges
    win = window(kind, ART)
    put(img, vgrad(CW, CH, p["edge"], p["edge2"], ART[1], ART[3]), minus(window(kind, grow(ART, 3)), win))
    put(img, flat(CW, CH, (12, 9, 7)), minus(window(kind, grow(ART, 1)), win))
    put(img, backdrop(kind), win)
    img = overlay(img, (0, 0, 0), inner_shadow(win, 4, 0.7))
    # the icon's frame, casting a shadow on the glow, and the hole the icon
    # shows through
    shadow = ImageChops.offset(rmask(CW, CH, grow(ICON, 5), 6), 0, 2 * S).filter(ImageFilter.GaussianBlur(4 * S))
    img = overlay(img, (0, 0, 0), ImageChops.multiply(shadow, Image.new("L", shadow.size, 170)))
    put(img, flat(CW, CH, (12, 9, 7)), rmask(CW, CH, grow(ICON, 5), 5))
    put(img, vgrad(CW, CH, p["edge"], p["edge2"], ICON[1] - 4, ICON[3] + 4), rmask(CW, CH, grow(ICON, 4), 4))
    stroke(img, CW, CH, grow(ICON, 4), 4, tuple(min(255, v + 40) for v in p["edge"]), 0.8)
    put(img, flat(CW, CH, (12, 9, 7)), rmask(CW, CH, grow(ICON, 1.2), 2.5))
    hole = rmask(CW, CH, ICON, 2)
    cut(img, hole)
    img = overlay(img, (0, 0, 0), inner_shadow(hole, 3, 0.45))
    # name banner across the bottom of the art
    put(img, vgrad(CW, CH, *p["banner"], NAME[1], NAME[3]), rmask(CW, CH, NAME, 3))
    stroke(img, CW, CH, NAME, 3, p["edge"], 2)
    stroke(img, CW, CH, grow(NAME, -2), 2, (10, 8, 6), 1)
    shine = minus(rmask(CW, CH, grow(NAME, -3), 2), rmask(CW, CH, [NAME[0] + 3, NAME[1] + 4.5, NAME[2] - 3, NAME[3]], 2))
    put(img, flat(CW, CH, (255, 255, 255)), ImageChops.multiply(shine, Image.new("L", shine.size, 40)))
    # type line, hanging under the banner
    tb = [TYPE[0], TYPE[1] - 6, TYPE[2], TYPE[3]]
    above = rmask(CW, CH, [0, 0, CW, TYPE[1] - 0.5], 0)
    put(img, flat(CW, CH, (10, 8, 6)), minus(rmask(CW, CH, tb, 7), above))
    inner = minus(rmask(CW, CH, grow(tb, -1.5), 5.5), rmask(CW, CH, [0, 0, CW, TYPE[1] + 0.5], 0))
    put(img, grain(vgrad(CW, CH, *p["plate"], TYPE[1], TYPE[3]), 3), inner)
    put(img, flat(CW, CH, p["edge"]), minus(rmask(CW, CH, grow(tb, -1.5), 5.5), rmask(CW, CH, grow(tb, -2.7), 4.3)))
    put(img, flat(CW, CH, p["edge"]), rmask(CW, CH, [NAME[0] + 2, NAME[3] - 1.2, NAME[2] - 2, NAME[3] + 0.6], 0))
    # rules box
    t = TEXT[kind]
    put(img, grain(grain(vgrad(CW, CH, *p["box"], t[1], t[3]), 8, blur=3), 4), rmask(CW, CH, t, 6))
    img = overlay(img, p["shade"], inner_shadow(rmask(CW, CH, t, 6), 5, 0.35))
    stroke(img, CW, CH, t, 6, p["boxedge"], 1.5)
    return finish(img, CW, CH, "CardUnit" if kind == "unit" else "CardTactic", (256, 512))


def card_rim():
    """The card's outer rim: grey, the addon tints it with the rarity colour."""
    img = new(CW, CH)
    outer = rmask(CW, CH, [0, 0, CW, CH], 15)
    put(img, flat(CW, CH, (14, 14, 14)), minus(outer, rmask(CW, CH, [8, 8, CW - 8, CH - 8], 9)))
    ring = minus(rmask(CW, CH, [1.5, 1.5, CW - 1.5, CH - 1.5], 13.5), rmask(CW, CH, [6.5, 6.5, CW - 6.5, CH - 6.5], 10))
    put(img, grain(vgrad(CW, CH, (255, 255, 255), (168, 168, 168)), 4), ring)
    stroke(img, CW, CH, [4, 4, CW - 4, CH - 4], 11.5, (132, 132, 132), 1)     # groove
    stroke(img, CW, CH, [1.5, 1.5, CW - 1.5, CH - 1.5], 13.5, (255, 255, 255), 0.8)
    return finish(img, CW, CH, "CardRim", (256, 512))


def card_glow():
    """A soft white glow round the card's outline, for ADD blending (hover,
    selected). It covers the card plus GLOW_PAD on every side, squeezed to
    256 wide at the top of a 256x512 texture."""
    pad = GLOW_PAD
    w, h = CW + 2 * pad, CH + 2 * pad
    m = Image.new("L", (w * S, h * S), 0)
    ImageDraw.Draw(m).rounded_rectangle([pad * S, pad * S, (w - pad) * S, (h - pad) * S], 15 * S, fill=255)
    band = ImageChops.subtract(m.filter(ImageFilter.MaxFilter(9)), m.filter(ImageFilter.MinFilter(9)))
    a = (np.asarray(band.filter(ImageFilter.GaussianBlur(9 * S)), "float32") / 255 * 3.6
         + np.asarray(band.filter(ImageFilter.GaussianBlur(1 * S)), "float32") / 255 * 0.5)
    inside = np.asarray(m.filter(ImageFilter.MinFilter(41)).filter(ImageFilter.GaussianBlur(4 * S)), "float32") / 255
    a = np.clip(a, 0, 1) * (1 - inside * 0.9)
    img = Image.new("RGBA", (w * S, h * S), (255, 255, 255, 0))
    img.putalpha(Image.fromarray((a * 255).astype("uint8"), "L"))
    gh = int(round(h * 256 / w))
    return finish(img, 256, gh, "CardGlow", (256, 512))


def shape_mask(n, kind, scale=1.0):
    m = Image.new("L", (n * S, n * S), 0)
    d = ImageDraw.Draw(m)
    c = n / 2

    def P(pts):
        return [((c + (x - c) * scale) * S, (c + (y - c) * scale) * S) for x, y in pts]
    if kind == "circle":
        r = (n / 2 - 2) * scale
        d.ellipse([(c - r) * S, (c - r) * S, (c + r) * S, (c + r) * S], fill=255)
    elif kind == "hex":
        d.polygon(P([(c, 2), (c + 28, 16), (c + 28, 48), (c, 62), (c - 28, 48), (c - 28, 16)]), fill=255)
    elif kind == "shield":
        pts = [(6, 6), (58, 6), (58, 30)]
        for i in range(1, 12):
            t = i / 12
            pts.append((58 - 26 * t ** 0.9, 30 + 30 * math.sin(t * math.pi / 2)))
        pts.append((32, 61))
        for i in range(11, 0, -1):
            t = i / 12
            pts.append((6 + 26 * t ** 0.9, 30 + 30 * math.sin(t * math.pi / 2)))
        d.polygon(P(pts), fill=255)
    elif kind == "diamond":
        d.polygon(P([(c, 2), (n - 3, c), (c, n - 2), (3, c)]), fill=255)
    return m


def jewel(name, kind, col, rim=(226, 190, 112), facets=0):
    """A stat badge in full colour (64x64): dark outline, a metal rim and a
    shaded, glossy face, cut into facets if asked."""
    n = 64
    img = new(n, n)
    put(img, flat(n, n, (12, 10, 8)), shape_mask(n, kind, 1.0))
    put(img, vgrad(n, n, rim, tuple(int(v * 0.45) for v in rim)), shape_mask(n, kind, 0.9))
    inner = shape_mask(n, kind, 0.76)
    yy, xx = np.mgrid[0:n * S, 0:n * S].astype("float32") / S
    c = n / 2
    shade = np.clip(1.28 - np.hypot(xx - c * 0.8, yy - c * 0.62) / n * 1.35, 0.42, 1.35)
    if facets:
        ang = np.arctan2(yy - c, xx - c)
        sector = np.floor((ang + math.pi) / (2 * math.pi / facets)).astype(int)
        shade = shade * np.where(sector % 2 == 0, 1.08, 0.9)
        shade = np.where(np.hypot(xx - c, yy - c) < n * 0.17, shade * 1.12, shade)
    rgb = np.array(col, "float32")[None, None, :] * shade[:, :, None]
    put(img, Image.fromarray(np.clip(rgb, 0, 255).astype("uint8"), "RGB"), inner)
    gloss = Image.new("L", (n * S, n * S), 0)
    ImageDraw.Draw(gloss).ellipse([n * 0.18 * S, n * 0.1 * S, n * 0.82 * S, n * 0.52 * S], fill=70)
    img = overlay(img, (255, 255, 255), ImageChops.multiply(gloss.filter(ImageFilter.GaussianBlur(3 * S)), inner))
    return finish(img, n, n, name)


def pill():
    """A soft-edged rounded bar (the dark backing behind a card's tag)."""
    w, h = 128, 32
    img = new(w, h)
    m = rmask(w, h, [1, 1, w - 1, h - 1], 12).filter(ImageFilter.GaussianBlur(1.2 * S))
    put(img, flat(w, h, (255, 255, 255)), m)
    return finish(img, w, h, "Pill")


def wind_rose(d, cx, cy, light, dark, bg):
    """The Tradewinds emblem: a wind rose, the compass star old sea charts
    used to mark the winds. Each point is split into a lit and a shaded half,
    so it reads as raised metal; the four winds between are shorter and sit
    behind. Plain shapes, so it still reads as a star at 16 pixels."""
    def P(r, a):
        return ((cx + r * math.cos(a)) * S, (cy + r * math.sin(a)) * S)

    def ring(r, col, width):
        d.ellipse(sc([cx - r, cy - r, cx + r, cy + r]), outline=col, width=int(width * S))
    ring(38, dark, 1.4)
    for i in range(32):                                  # the 32 compass points, as ticks
        a = i * math.pi / 16
        r0 = 33.5 if i % 4 == 0 else 35.5
        d.line([P(r0, a), P(38, a)], fill=dark, width=int(1.1 * S))
    for length, base, offset in ((33, 8.5, math.pi / 4), (49, 11, 0)):
        for i in range(4):
            a = -math.pi / 2 + offset + i * math.pi / 2
            tip, left, right = P(length, a), P(base, a - math.pi / 4), P(base, a + math.pi / 4)
            d.polygon([P(0, a), tip, left], fill=light)
            d.polygon([P(0, a), tip, right], fill=dark)
            d.line([left, tip, right], fill=bg, width=int(0.9 * S))
    d.ellipse(sc([cx - 6.5, cy - 6.5, cx + 6.5, cy + 6.5]), fill=bg)
    d.ellipse(sc([cx - 4.5, cy - 4.5, cx + 4.5, cy + 4.5]), fill=light)


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
    wind_rose(d, cx, cy, (242, 210, 124, 255), (170, 128, 56, 255), (12, 18, 42, 255))
    return finish(img, CW, CH, "CardBack", (256, 512))


def card_art():
    """Every texture of the card face. Returns them for the preview sheet."""
    return {
        "unit": card_body("unit"), "tactic": card_body("tactic"), "rim": card_rim(), "glow": card_glow(),
        "back": card_back(), "pill": pill(),
        "cost": jewel("StatCost", "circle", (52, 112, 236), facets=8),
        "atk": jewel("StatAttack", "hex", (236, 162, 42)),
        "hp": jewel("StatHealth", "shield", (214, 44, 40)),
        "gem": jewel("RarityGem", "diamond", (240, 240, 240), rim=(200, 200, 200), facets=4),
    }


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
    """A prismatic ring over the card's rim (same layout as CardRim),
    drawn with ADD blending on holographic cards."""
    img = new(CW, CH)
    ring = minus(rmask(CW, CH, [1.5, 1.5, CW - 1.5, CH - 1.5], 13.5), rmask(CW, CH, [6.5, 6.5, CW - 6.5, CH - 6.5], 10))
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
def font(size, bold=True):
    for name in (("arialbd.ttf", "georgiab.ttf") if bold else ("arial.ttf",)):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()



# ---------------------------------------------------------------------------
# Preview sheet: sample cards laid out the way UI/Widgets.lua lays them out,
# at R screen pixels per UI unit (2.1 is a 4K screen at UI scale 0.75, 1.4 a
# 1080p one at UI scale 1). Uses the game's font if it can find a copy: set
# TRADEWINDS_FONT to the path of a frizqt__.ttf (some addons ship one).
FONTS = [f for f in (os.environ.get("TRADEWINDS_FONT"), "frizqt__.ttf", "arial.ttf") if f]
CARD_W, CARD_H = 112, 156
K = CARD_W / CW
RARITY = {"common": (204, 204, 204), "uncommon": (30, 255, 0), "rare": (51, 140, 255), "epic": (178, 76, 255),
          "legendary": (255, 128, 0)}
RIM = {"common": (158, 158, 158), "uncommon": (69, 189, 56), "rare": (66, 128, 242), "epic": (163, 87, 230),
       "legendary": (245, 143, 31)}


def mock_font(size):
    for name in FONTS:
        try:
            return ImageFont.truetype(name, max(1, int(round(size))))
        except OSError:
            pass
    return ImageFont.load_default()


def tint(img, col):
    r, g, b, a = img.split()

    def f(ch, c):
        return ch.point(lambda v: v * c // 255)
    return Image.merge("RGBA", (f(r, col[0]), f(g, col[1]), f(b, col[2]), a))


def fit_text(img, box, paras, size, smallest, R, outline=False, wrap=True):
    """Like UI.FitText: wrap into the box, a point smaller until it fits."""
    x, y, w, h = box
    while True:
        f = mock_font(size * R)
        lines = []
        for text, col in paras:
            cur = ""
            for word in text.split(" "):
                t = (cur + " " + word).strip()
                if not wrap or not cur or f.getlength(t) <= w * R:
                    cur = t
                else:
                    lines.append((cur, col))
                    cur = word
            lines.append((cur, col))
        fits = len(lines) * size * 1.1 <= h + 0.5 and all(f.getlength(t) <= w * R + 0.5 for t, _ in lines)
        if fits or size <= smallest:
            break
        size -= 1
    d = ImageDraw.Draw(img)
    top = y + (h - len(lines) * size * 1.1) / 2
    for i, (t, col) in enumerate(lines):
        pos = ((x + w / 2) * R, (top + (i + 0.5) * size * 1.1) * R)
        if outline:
            d.text(pos, t, font=f, fill=col, anchor="mm", stroke_width=max(1, int(R)), stroke_fill=(0, 0, 0))
        else:
            d.text(pos, t, font=f, fill=col, anchor="mm")


def mock_card(c, art, R):
    def sized(img, w, h):
        return img.resize((max(1, int(round(w * R))), max(1, int(round(h * R)))), Image.LANCZOS)

    def units(b, inset=(0, 0, 0, 0)):
        return (b[0] + inset[0]) * K, (b[1] + inset[1]) * K, (b[2] - b[0] - inset[0] - inset[2]) * K, \
            (b[3] - b[1] - inset[1] - inset[3]) * K
    unit = c["type"] == "unit"
    kind = "unit" if unit else "tactic"
    img = Image.new("RGBA", (int(CARD_W * R), int(CARD_H * R)), (0, 0, 0, 0))
    ax, ay, aw, ah = units(ICON)
    pic = vgrad(64, 64, c["hue"], tuple(v // 3 for v in c["hue"])).resize((64, 64)).convert("RGBA")
    ImageDraw.Draw(pic).ellipse([14, 10, 50, 70], fill=tuple(min(255, v + 60) for v in c["hue"]) + (255,))
    img.alpha_composite(sized(pic, aw, ah), (int(ax * R), int(ay * R)))
    img.alpha_composite(sized(art[kind], CARD_W, CARD_H))
    img.alpha_composite(sized(tint(art["rim"], RIM[c["rarity"]]), CARD_W, CARD_H))
    fit_text(img, units(NAME, (8, 1, 8, 1)), [(c["name"], (252, 244, 222))], 11, 7, R)
    fit_text(img, units(TYPE, (5, 0, 5, 1)), [(c["typeline"], (255, 236, 196) if unit else (232, 234, 255))],
             9, 6, R, wrap=False)
    area = units(TEXT[kind], (7, 4, 7, 26 if unit else 6))
    paras = []
    if c.get("kw"):
        paras.append((c["kw"], (24, 58, 120) if unit else (60, 40, 130)))
    if c.get("short"):
        paras.append((c["short"], (40, 28, 16) if unit else (30, 26, 50)))
    if paras:
        fit_text(img, area, paras, 10, 7, R)
    elif c.get("flavor"):
        fit_text(img, area, [("\u201c" + c["flavor"] + "\u201d", (120, 96, 66))], 9, 7, R)
    g = 13
    img.alpha_composite(sized(tint(art["gem"], RARITY[c["rarity"]]), g, g),
                        (int((CARD_W - g) / 2 * R), int((GEM_Y[kind] * K - g / 2) * R)))
    for key, (cx, cy), val in (("cost", (14, 14), c["cost"]), ("atk", (15, CARD_H - 16), c.get("atk")),
                               ("hp", (CARD_W - 15, CARD_H - 16), c.get("hp"))):
        if val is not None:
            img.alpha_composite(sized(art[key], 30, 30), (int((cx - 15) * R), int((cy - 15) * R)))
            fit_text(img, (cx - 15, cy - 15.5, 30, 30), [(str(val), (255, 255, 255))], 16, 16, R, outline=True)
    return img


def mock(path, art, R=2.1):
    cards = [
        dict(name="Kobold Vermin", type="unit", typeline="Unit", rarity="common", cost=1, atk=1, hp=2,
             flavor="You no take candle!", hue=(110, 84, 60)),
        dict(name="Plainstrider", type="unit", typeline="Beast unit", rarity="uncommon", cost=2, atk=1, hp=3,
             short="Arrive: restore 2 Morale", hue=(140, 116, 70)),
        dict(name="Booty Bay Bruiser", type="unit", typeline="Unit", rarity="rare", cost=4, atk=3, hp=5,
             kw="Guard, Sturdy", hue=(70, 104, 128)),
        dict(name="Edwin VanCleef", type="unit", typeline="Defias unit", rarity="legendary", cost=4, atk=4, hp=3,
             kw="Swift, Stealth, Pierce", short="Arrive: draw a card", hue=(84, 60, 96)),
        dict(name="Fireball", type="tactic", typeline="Tactic: enemy lane", rarity="common", cost=2,
             short="3 damage, or 2 to Morale if empty", hue=(180, 80, 34)),
        dict(name="Bandage", type="tactic", typeline="Tactic: your unit", rarity="uncommon", cost=1,
             short="Fully heal a unit. Restore 2 Morale", hue=(160, 150, 128)),
        dict(name="Blizzard", type="tactic", typeline="Tactic", rarity="epic", cost=5,
             short="2 damage to every enemy unit", hue=(70, 124, 190)),
    ]
    faces = [mock_card(c, art, R) for c in cards]
    back = art["back"].resize(faces[0].size, Image.LANCZOS)
    faces.append(back)
    gap = int(10 * R)
    sheet = Image.new("RGBA", (len(faces) * (faces[0].width + gap) + gap, faces[0].height + 2 * gap), (0, 0, 0, 255))
    wood = Image.open(OUT / "Board.tga").convert("RGBA")
    for x in range(0, sheet.width, wood.width):
        for y in range(0, sheet.height, wood.height):
            sheet.paste(wood, (x, y))
    sheet = Image.blend(sheet, Image.new("RGBA", sheet.size, (0, 0, 0, 255)), 0.3)
    for i, f in enumerate(faces):
        sheet.alpha_composite(f, (gap + i * (f.width + gap), gap))
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
    art = card_art()
    board()
    star()
    holo_foil()
    holo_ring()
    dia = diagrams()
    fx_all()
    print("wrote", ", ".join(sorted(p.name for p in OUT.glob("*.tga"))))
    if len(sys.argv) > 1:
        mock(sys.argv[1], art, float(sys.argv[2]) if len(sys.argv) > 2 else 2.1)
        print("mock:", sys.argv[1])
        sheet = Image.new("RGBA", (DW * 3 + 40, (DH + 10) * 4 + 10), (30, 26, 22, 255))
        for i, im in enumerate(dia):
            sheet.alpha_composite(im, (10 + (i % 3) * (DW + 10), 10 + (i // 3) * (DH + 10)))
        p = pathlib.Path(sys.argv[1])
        sheet.save(p.with_name(p.stem + "_diagrams.png"))
