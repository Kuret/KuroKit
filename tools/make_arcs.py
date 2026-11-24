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
    }
    for name, img in images.items():
        save(img, name + "Left")
        save(img.transpose(Image.FLIP_LEFT_RIGHT), name + "Right")
    cast = (CAST_W, CAST_H)
    save(back(cast, cast_point, [CAST], CAST_HALF_ANGLE), "ArcCastBack")
    save(fill(cast, cast_point, CAST, CAST_HALF_ANGLE, (CAST_CX, CAST_CY)), "ArcCast")
    for name, (top, bottom) in RING_METALS.items():
        save(ring(top, bottom), name)


if __name__ == "__main__":
    main()
