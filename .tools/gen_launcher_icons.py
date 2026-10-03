"""Generates the Imo LIVE launcher icons.

The artwork mirrors the in-app brand mark so the home screen, the Android launch
window (drawable/launch_mark.xml) and the Flutter splash logo
(_LogoPainter in splash_screen.dart) all show the same identity.

Geometry is taken from _LogoPainter: a rounded speech bubble with a bottom-left
tail, containing a "live" broadcast pulse (centre dot + two arcs) punched out in
the accent-dark colour.
"""

import os

from PIL import Image, ImageDraw

ACCENT = (255, 45, 85, 255)          # #FF2D55
ACCENT_DARK = (190, 26, 60, 255)     # #BE1A3C, the gradient end / cut colour

# Launcher icons are square; Android masks them, so keep content inside a safe
# circular zone (~72% of the width) to survive circle/squircle masks.
SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

SS = 8  # supersample factor for smooth edges


def _draw_mark(size: int) -> Image.Image:
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # The icon fills the canvas with the accent colour and draws the mark in
    # white, matching the launch mark's look on a full-bleed square.
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.22), fill=ACCENT)

    # Content box: the mark occupies the middle ~62% so it survives masking.
    m = s * 0.19
    w = s - 2 * m
    x0, y0 = m, m

    def px(fx: float) -> float:
        return x0 + w * fx

    def py(fy: float) -> float:
        return y0 + w * fy

    white = (255, 255, 255, 255)

    # --- Speech bubble body (rounded, bottom-left corner tighter for the tail)
    bx0, by0 = px(0.0), py(0.0)
    bx1, by1 = px(1.0), py(0.72)
    d.rounded_rectangle(
        [bx0, by0, bx1, by1],
        radius=w * 0.20,
        fill=white,
    )

    # --- Tail: a triangle from the bubble's bottom-left down to a point
    d.polygon(
        [
            (px(0.16), py(0.66)),
            (px(0.16), py(1.0)),
            (px(0.46), py(0.70)),
        ],
        fill=white,
    )

    # --- "Live" pulse punched out of the white bubble in accent-dark
    cx, cy = px(0.5), py(0.34)
    dot_r = w * 0.070
    d.ellipse(
        [cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r],
        fill=ACCENT_DARK,
    )

    # Two arcs to the right of the dot. PIL has no arc-with-thickness, so draw a
    # stroked arc by stamping circles along the path.
    def stroked_arc(radius: float, thickness: float, colour) -> None:
        steps = 90
        for i in range(steps + 1):
            t = i / steps
            ang = -0.95 + t * 1.90  # radians, mirrored about the vertical
            import math

            ax = cx + math.cos(ang) * radius
            ay = cy + math.sin(ang) * radius
            r = thickness / 2.0
            d.ellipse([ax - r, ay - r, ax + r, ay + r], fill=colour)

    stroked_arc(radius=w * 0.175, thickness=w * 0.075, colour=ACCENT_DARK)

    faint = (190, 26, 60, 150)
    stroked_arc(radius=w * 0.290, thickness=w * 0.060, colour=faint)

    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    root = "android/app/src/main/res"
    for density, size in SIZES.items():
        out_dir = os.path.join(root, f"mipmap-{density}")
        os.makedirs(out_dir, exist_ok=True)
        icon = _draw_mark(size)
        path = os.path.join(out_dir, "ic_launcher.png")
        icon.save(path, "PNG", optimize=True)
        print(f"wrote {path} ({size}x{size})")


if __name__ == "__main__":
    main()
