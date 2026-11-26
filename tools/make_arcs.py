"""Generates the arc HUD textures (KuroKit/Media/Arc*.tga).

Side arcs: a "(" shaped pair of rings (outer: health, inner: power) on a
256 x 512 canvas, and the same mirrored for the right side. Cast arc: a
smile-shaped ring on a 512 x 128 canvas. For each: a white fill (tinted in
game; a status bar crops it, so it fills along the curve), shaded like the
cast bar's fill but following the curve: darker edges, a glossy band toward
the outer edge and fine streaks running along the arc; and a
back in the Forever plate's materials: dark outline, bronze line (lighter at
the top), dark rim / empty track. Every end has rounded corners (Forever has
no sharp ones) and fill and track carry a fine grain.

The side arcs' back has a round socket for the portrait on the arcs' top end,
its outline, bronze line and dark rim one with the arcs'; the side fills end
in the socket's hole (cut out: the portrait over them is see-through), so
full meets the portrait's edge.

Trims: thin rings along the player arc (the five-second rule / tick and pet
health inside the power ring), each on its own 128 x 512 canvas covering exactly its height from its
lower tip to just below the socket (so the HUD's status bar maps 0..1 straight
onto it; the HUD computes the same placement: ArcHUD.lua TRIMS).

ArcPipBack / ArcPipFill (32 x 32): a combo point socket (outline, bronze
line, dark well) and its gem (white, shaded, for tinting).

ArcMiniBack / ArcMiniFill (64 x 256): a short arc beside your character, ( shaped,
in the arcs' materials (the shield draining); the fill cut to its own rows
and stretched to the canvas, so a status bar over just those rows maps
values straight onto it. ArcGlow: a soft ring round the portrait socket
(shown while you have a shield).

Portrait rings: a round frame (outline, bronze / gold / silver line, dark
rim) on a 128 x 128 canvas, its hole for a round portrait (ArcRing,
ArcRingElite, ArcRingRare).

Run with any Python that has Pillow:  python tools/make_arcs.py
"""
import math
import os
import random

from PIL import Image, ImageDraw

SS = 4  # supersampling
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "KuroKit", "Media")

OUTLINE = (0, 0, 0, 220)
RIM = (12, 12, 12, 235)
BRONZE_TOP = (230, 192, 132)
BRONZE_BOTTOM = (132, 94, 54)
OUTLINE_W, BRONZE_W, RIM_W = 8, 5, 2  # expansion of each layer around the rings (px): outline 3, bronze 3, rim 2
SHADE_EDGE_OUT, SHADE_EDGE_IN, SHADE_BANDS = 0.62, 0.55, 24  # fill brightness at the ring's edges
CORNER = {"outline": 7, "bronze": 6, "rim": 5, "fill": 4}  # corner radius of each layer (px)
GRAIN_FILL, GRAIN_TRACK = 0.07, 0.12                        # +- brightness of the grain
GLOSS_AT, GLOSS_WIDTH, GLOSS = 0.68, 0.16, 0.22             # glossy band: where across the ring (0 inner .. 1 outer), how wide, how bright
STREAK = 0.07                                               # +- brightness of the streaks along the arc

# Side arcs (left; the right ones are mirrored).
SIDE_W, SIDE_H = 256, 512
SIDE_CX, SIDE_CY = 412, 256
HALF_ANGLE = math.radians(36)
OUTER = (372, 400)   # health ring radii
INNER = (347, 365)   # power ring radii (gap 7: rim, bronze, rim)
# (Angles here: positive is up, side_point's y = centre - r sin a.)
SOCKET_ANGLE = math.radians(30)   # the portrait socket's centre on the rings' middle line (radius 373)
SOCKET_R = 50                     # its hole (the portrait's radius)
FILL_TOP = SOCKET_ANGLE           # the side fills' top end: under the portrait

# Cast arc.
CAST_W, CAST_H = 512, 128
CAST_CX, CAST_CY = 256, -484
CAST_HALF_ANGLE = math.radians(17)
CAST = (580, 600)


# Swing arcs: thin arcs in the cast arc's style and curve, on their own
# canvas with the ring in its middle (ArcHUD/Swing.lua SWING_*: the same
# numbers).
SWING_W, SWING_H = 512, 64
SWING_CX, SWING_CY = 256, -551
SWING = (592, 600)


def swing_point(r, a):
    return (SWING_CX + r * math.sin(a)) * SS, (SWING_CY + r * math.cos(a)) * SS


def side_point(r, a):
    return (SIDE_CX - r * math.cos(a)) * SS, (SIDE_CY - r * math.sin(a)) * SS


def cast_point(r, a):
    return (CAST_CX + r * math.sin(a)) * SS, (CAST_CY + r * math.cos(a)) * SS


def bezier(p0, c, p1, n=12):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1])
            for t in (i / n for i in range(n + 1))]


def sector(point, r_in, r_out, half, corner=0, steps=160, a0=None, a1=None):
    """A ring segment from -half to +half (or a0 to a1), its four corners rounded."""
    a0 = -half if a0 is None else a0
    a1 = half if a1 is None else a1
    span = a1 - a0
    rc = min(corner, (r_out - r_in) / 2)
    if rc <= 0:
        outer = [point(r_out, a0 + span * i / steps) for i in range(steps + 1)]
        inner = [point(r_in, a1 - span * i / steps) for i in range(steps + 1)]
        return outer + inner
    ao, ai = rc / r_out, rc / r_in  # the corner's length along each arc, as an angle
    pts = bezier(point(r_out - rc, a0), point(r_out, a0), point(r_out, a0 + ao))
    pts += [point(r_out, a0 + ao + (span - 2 * ao) * i / steps) for i in range(1, steps)]
    pts += bezier(point(r_out, a1 - ao), point(r_out, a1), point(r_out - rc, a1))
    pts += bezier(point(r_in + rc, a1), point(r_in, a1), point(r_in, a1 - ai))
    pts += [point(r_in, a1 - ai - (span - 2 * ai) * i / steps) for i in range(1, steps)]
    pts += bezier(point(r_in, a0 + ai), point(r_in, a0), point(r_in + rc, a0))
    return pts


def circle(center, r, steps=120):
    cx, cy = center
    return [(cx + r * SS * math.cos(2 * math.pi * i / steps), cy + r * SS * math.sin(2 * math.pi * i / steps))
            for i in range(steps)]


def grain(img, amount, seed):
    """Fine random brightness grain on the opaque pixels."""
    rng = random.Random(seed)
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a:
                f = 1 + rng.uniform(-amount, amount)
                px[x, y] = (min(255, round(r * f)), min(255, round(g * f)), min(255, round(b * f)), a)
    return img


def mask(size, polygons, holes=()):
    m = Image.new("L", (size[0] * SS, size[1] * SS), 0)
    d = ImageDraw.Draw(m)
    for poly in polygons:
        d.polygon(poly, fill=255)
    for poly in holes:
        d.polygon(poly, fill=0)
    return m.resize(size, Image.LANCZOS)


def solid(size, color, m):
    layer = Image.new("RGBA", size, color[:3] + (0,))
    alpha = m.point(lambda v: v * color[3] // 255)
    layer.putalpha(alpha)
    return layer


def gradient(size, top, bottom, m):
    w, h = size
    layer = Image.new("RGBA", size)
    px = layer.load()
    for y in range(h):
        t = y / (h - 1)
        c = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = c + (255,)
    layer.putalpha(m)
    return layer


def back(size, point, rings, half, socket=False):
    """The rings' outline, bronze line and dark rim / track; with `socket`, a
    round portrait socket on their top end in the same layers."""
    lo, hi = min(r[0] for r in rings), max(r[1] for r in rings)
    mid = (lo + hi) / 2
    centre = point(mid, SOCKET_ANGLE)

    def with_socket(polys, expand):
        return polys + [circle(centre, SOCKET_R + expand)] if socket else polys

    img = Image.new("RGBA", size, (0, 0, 0, 0))
    img.alpha_composite(solid(size, OUTLINE, mask(size, with_socket([
        sector(point, lo - OUTLINE_W, hi + OUTLINE_W, half + OUTLINE_W / mid, CORNER["outline"])], OUTLINE_W))))
    img.alpha_composite(gradient(size, BRONZE_TOP, BRONZE_BOTTOM, mask(size, with_socket([
        sector(point, lo - BRONZE_W, hi + BRONZE_W, half + BRONZE_W / mid, CORNER["bronze"])], BRONZE_W))))
    img.alpha_composite(grain(solid(size, RIM, mask(size, with_socket([
        sector(point, r[0] - RIM_W, r[1] + RIM_W, half + RIM_W / mid, CORNER["rim"]) for r in rings], RIM_W))),
        GRAIN_TRACK, 1))
    return img


def fill(size, point, ring, half, center, top=None, hole=None):
    """White ring in the cast bar's style along the curve: per pixel, the
    brightness depends on how far across the ring it is (darker edges, a
    glossy band) plus a streak value per radius (so streaks run along the
    arc); the shape (rounded ends) from the polygon mask, less the `hole`
    polygon."""
    r_in, r_out = ring
    cx, cy = center
    shape = mask(size, [sector(point, r_in, r_out, half, CORNER["fill"], a1=top)], [hole] if hole else ())
    rng = random.Random(3)
    streaks = [rng.uniform(-STREAK, STREAK) for _ in range(int((r_out - r_in) * 2) + 2)]
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    px, alpha = img.load(), shape.load()
    w, h = size
    for y in range(h):
        for x in range(w):
            a = alpha[x, y]
            if not a:
                continue
            r = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            t = min(1, max(0, (r - r_in) / (r_out - r_in)))   # 0 inner edge .. 1 outer edge
            edge = SHADE_EDGE_IN + (SHADE_EDGE_OUT - SHADE_EDGE_IN) * t
            v = edge + (1 - edge) * math.sin(math.pi * t) ** 0.7
            v += GLOSS * math.exp(-((t - GLOSS_AT) / GLOSS_WIDTH) ** 2)
            v += streaks[min(len(streaks) - 1, int((r - r_in) * 2))]
            v = round(255 * min(1, max(0, v / (1 + GLOSS))))
            px[x, y] = (v, v, v, a)
    return grain(img, GRAIN_FILL, 2)


ARC_R = 373                          # the socket's centre radius as the HUD has it
TRIM_CLEAR = SOCKET_R + OUTLINE_W + 2  # trims end where they'd meet this circle round the socket
TRIM_W, TRIM_H, TRIM_MARGIN = 128, 512, 2
TRIMS = {
    "ArcTrimTick": (329, 335),
    "ArcTrimPet": (319, 325),
}


def trim_top(r_in, r_out):
    """The trim's top end (angle, up positive): clear of the socket."""
    best = 0
    for r in (r_in, r_out):
        c = (r * r + ARC_R * ARC_R - TRIM_CLEAR ** 2) / (2 * r * ARC_R)
        if c < 1:
            best = max(best, math.acos(c))
    return SOCKET_ANGLE - best


def trim(r_in, r_out):
    top = trim_top(r_in, r_out)
    y_top = SIDE_CY - r_out * math.sin(top)
    y_bottom = SIDE_CY + r_out * math.sin(HALF_ANGLE)
    k = TRIM_H / (y_bottom - y_top)
    x_min = SIDE_CX - r_out - TRIM_MARGIN
    cx, cy = (SIDE_CX - x_min) * k, (SIDE_CY - y_top) * k

    def point(r, a):
        return (cx - r * math.cos(a)) * SS, (cy - r * math.sin(a)) * SS
    return fill((TRIM_W, TRIM_H), point, (r_in * k, r_out * k), HALF_ANGLE, (cx, cy), top=top)


# The mini arc beside your character (ArcHUD.lua T.MINI_*: the same numbers).
MINI_W, MINI_H = 64, 256
MINI_RING, MINI_HALF = (214, 226), math.radians(24)
MINI_CX, MINI_CY = 236, 128          # its circle's centre: the outer edge's middle 10 px from the left


def mini_point(r, a):
    return (MINI_CX - r * math.cos(a)) * SS, (MINI_CY - r * math.sin(a)) * SS


def mini_rows():
    reach = MINI_RING[1] * math.sin(MINI_HALF)
    return math.floor(MINI_CY - reach), math.ceil(MINI_CY + reach)


def mini_fill():
    size = (MINI_W, MINI_H)
    full = fill(size, mini_point, MINI_RING, MINI_HALF, (MINI_CX, MINI_CY))
    top, bottom = mini_rows()
    return full.crop((0, top, MINI_W, bottom)).resize(size, Image.LANCZOS)


GLOW_CANVAS, GLOW_R, GLOW_SIGMA = 128, 46, 3.5   # a soft ring (radius, softness px): its outer glow fades out well inside the canvas


PIP_CANVAS, PIP_GEM = 32, 8.5   # combo point: canvas, gem radius (px)


def disc_mask(size, r):
    c = size / 2 * SS
    m = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(m).ellipse((c - r * SS, c - r * SS, c + r * SS, c + r * SS), fill=255)
    return m.resize((size, size), Image.LANCZOS)


def pip_back():
    size = (PIP_CANVAS, PIP_CANVAS)
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    img.alpha_composite(solid(size, OUTLINE, disc_mask(PIP_CANVAS, PIP_GEM + 6.5)))
    img.alpha_composite(gradient(size, BRONZE_TOP, BRONZE_BOTTOM, disc_mask(PIP_CANVAS, PIP_GEM + 4)))
    img.alpha_composite(grain(solid(size, RIM, disc_mask(PIP_CANVAS, PIP_GEM + 1.5)), GRAIN_TRACK, 1))
    return img


def pip_fill():
    """A round gem: brighter towards its upper left, a small highlight."""
    size = (PIP_CANVAS, PIP_CANVAS)
    shape = disc_mask(PIP_CANVAS, PIP_GEM).load()
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    px = img.load()
    c = PIP_CANVAS / 2
    for y in range(PIP_CANVAS):
        for x in range(PIP_CANVAS):
            a = shape[x, y]
            if not a:
                continue
            dx, dy = (x + 0.5 - c) / PIP_GEM, (y + 0.5 - c) / PIP_GEM
            d = min(1, math.hypot(dx, dy))
            v = 0.62 + 0.38 * (1 - d * d)                          # rounder in the middle
            v += 0.35 * math.exp(-((dx + 0.35) ** 2 + (dy + 0.4) ** 2) / 0.06)  # highlight
            v = round(255 * min(1, v))
            px[x, y] = (v, v, v, a)
    return img


def glow():
    size = (GLOW_CANVAS, GLOW_CANVAS)
    img = Image.new("RGBA", size, (255, 255, 255, 0))
    px = img.load()
    c = GLOW_CANVAS / 2
    for y in range(GLOW_CANVAS):
        for x in range(GLOW_CANVAS):
            d = math.hypot(x + 0.5 - c, y + 0.5 - c) - GLOW_R
            a = math.exp(-(d / GLOW_SIGMA) ** 2 / 2) if d < 0 else math.exp(-(d / (GLOW_SIGMA * 1.6)) ** 2 / 2)
            px[x, y] = (255, 255, 255, round(255 * a))
    return img


def rim(size):
    """The side arcs' frame lines (outline, bronze line and rims round the
    rings and the socket) in white, the rings and the portrait cut out: tinted
    over the arc (threat)."""
    lo, hi = INNER[0], OUTER[1]
    mid = (lo + hi) / 2
    centre = side_point(mid, SOCKET_ANGLE)
    m = mask(size, [sector(side_point, lo - OUTLINE_W, hi + OUTLINE_W, HALF_ANGLE + OUTLINE_W / mid, CORNER["outline"]),
                    circle(centre, SOCKET_R + OUTLINE_W)],
             [sector(side_point, r[0], r[1], HALF_ANGLE, CORNER["fill"]) for r in (OUTER, INNER)]
             + [circle(centre, SOCKET_R)])
    return solid(size, (255, 255, 255, 255), m)


RING_CANVAS, RING_HOLE = 128, 52  # portrait ring: canvas, hole radius (px)
RING_METALS = {
    "ArcRing": (BRONZE_TOP, BRONZE_BOTTOM),
    "ArcRingElite": ((255, 230, 115), (190, 140, 30)),
    "ArcRingRare": ((235, 240, 255), (128, 133, 148)),
}


def ring(top, bottom):
    size = (RING_CANVAS, RING_CANVAS)
    c = RING_CANVAS / 2 * SS

    def disc(r):
        m = Image.new("L", (RING_CANVAS * SS, RING_CANVAS * SS), 0)
        ImageDraw.Draw(m).ellipse((c - r * SS, c - r * SS, c + r * SS, c + r * SS), fill=255)
        return m

    def annulus(r_in, r_out):
        m = disc(r_out)
        m.paste(0, mask=disc(r_in))
        return m.resize(size, Image.LANCZOS)

    hole = RING_HOLE
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    img.alpha_composite(solid(size, OUTLINE, annulus(hole - 1, hole + 3 + (OUTLINE_W - RIM_W))))
    img.alpha_composite(gradient(size, top, bottom, annulus(hole + RIM_W - 1, hole + RIM_W + (BRONZE_W - RIM_W))))
    img.alpha_composite(solid(size, RIM, annulus(hole - 1, hole + RIM_W)))
    return img


def save(img, name):
    img.save(os.path.join(OUT, name + ".tga"))
    print("wrote", name)


def main():
    os.makedirs(OUT, exist_ok=True)
    side = (SIDE_W, SIDE_H)
    socket = circle(side_point((INNER[0] + OUTER[1]) / 2, SOCKET_ANGLE), SOCKET_R)
    images = {
        "ArcBack": back(side, side_point, [OUTER, INNER], HALF_ANGLE, socket=True),
        "ArcOuter": fill(side, side_point, OUTER, HALF_ANGLE, (SIDE_CX, SIDE_CY), top=FILL_TOP, hole=socket),
        "ArcInner": fill(side, side_point, INNER, HALF_ANGLE, (SIDE_CX, SIDE_CY), top=FILL_TOP, hole=socket),
        "ArcRim": rim(side),
    }
    for name, img in images.items():
        save(img, name + "Left")
        save(img.transpose(Image.FLIP_LEFT_RIGHT), name + "Right")
    for name, (r_in, r_out) in TRIMS.items():
        save(trim(r_in, r_out), name)
    save(back((MINI_W, MINI_H), mini_point, [MINI_RING], MINI_HALF), "ArcMiniBack")
    save(mini_fill(), "ArcMiniFill")
    save(glow(), "ArcGlow")
    save(pip_back(), "ArcPipBack")
    save(pip_fill(), "ArcPipFill")
    cast = (CAST_W, CAST_H)
    save(back(cast, cast_point, [CAST], CAST_HALF_ANGLE), "ArcCastBack")
    cast_fill = fill(cast, cast_point, CAST, CAST_HALF_ANGLE, (CAST_CX, CAST_CY))
    save(cast_fill, "ArcCast")
    # The fill cut to its own columns, stretched to the canvas: a status bar
    # over just those columns fills from the arc's first pixel to its last
    # (ArcHUD.lua CastColumns: the same numbers).
    reach = CAST[1] * math.sin(CAST_HALF_ANGLE)
    left, right = math.floor(CAST_CX - reach), math.ceil(CAST_CX + reach)
    save(cast_fill.crop((left, 0, right, CAST_H)).resize(cast, Image.LANCZOS), "ArcCastFill")
    swing = (SWING_W, SWING_H)
    save(back(swing, swing_point, [SWING], CAST_HALF_ANGLE), "ArcSwingBack")
    swing_fill = fill(swing, swing_point, SWING, CAST_HALF_ANGLE, (SWING_CX, SWING_CY))
    reach = SWING[1] * math.sin(CAST_HALF_ANGLE)
    left, right = math.floor(SWING_CX - reach), math.ceil(SWING_CX + reach)
    save(swing_fill.crop((left, 0, right, SWING_H)).resize(swing, Image.LANCZOS), "ArcSwingFill")
    for name, (top, bottom) in RING_METALS.items():
        save(ring(top, bottom), name)


if __name__ == "__main__":
    main()
