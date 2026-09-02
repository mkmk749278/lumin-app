#!/usr/bin/env python3
"""Generate every Lumin brand bitmap from one geometric definition.

Why this exists
---------------
Until 2026-09-02 the app shipped ``flutter create``'s stock Flutter chevron as
its launcher icon on Play and as all four PWA icons, and cold-started on the
template's white ``launch_background``.  ``android/`` is not checked in — CI
regenerates it every run — so there was nowhere to *put* an icon until the
workflow gained a step that copies one in.  This script produces what that
step copies.

The mark is not invented here.  It is the one already drawn in
``lib/features/onboarding/pages/welcome_page.dart`` on welcome slide 1: an
accent-cyan rounded tile with a Black-weight ``L`` knocked out in the app's
deepest navy.  That mark previously existed on exactly one screen; this makes
it the launcher, the splash, the favicon and the PWA icon set as well.

The glyph is built from two rectangles rather than set in a font, so it is
crisp at 48px, identical across every density, and does not depend on a font
being installed on the CI runner.  Proportions follow a Black-weight
grotesque ``L`` (stem ~0.32 of cap height, foot ~0.71 wide, ~0.29 tall).

Regenerate with::

    python3 tool/gen_brand_assets.py

Outputs are committed — CI copies them, it does not run this script, so a
runner without Pillow can still build.
"""
from __future__ import annotations

import os
from PIL import Image, ImageDraw

# --- tokens, mirrored from lib/shared/tokens.dart -------------------------
ACCENT = (0x7B, 0xD3, 0xF7, 255)   # LuminColors.accent
BG_DEEP = (0x0A, 0x0E, 0x1A, 255)  # LuminColors.bgDeep
TRANSPARENT = (0, 0, 0, 0)

# Tile corner radius as a fraction of the tile: LuminRadii.lg (16) on the
# 72px welcome-slide mark.
TILE_RADIUS = 16 / 72

# Glyph geometry, as fractions of the box the glyph is fitted to.
CAP_H = 0.46      # cap height
STEM_W = 0.145    # vertical stroke width
FOOT_W = 0.315    # total glyph width (stem + foot)
FOOT_H = 0.135    # horizontal stroke height

SS = 4            # supersample factor; downscaled with LANCZOS


def _draw_l(draw: ImageDraw.ImageDraw, cx: float, cy: float,
            box: float, colour: tuple[int, int, int, int]) -> None:
    """Draw the L centred on (cx, cy), scaled so ``box`` is the reference size."""
    h = CAP_H * box
    w = FOOT_W * box
    stem = STEM_W * box
    foot = FOOT_H * box
    left = cx - w / 2
    top = cy - h / 2
    draw.rectangle([left, top, left + stem, top + h], fill=colour)
    draw.rectangle([left, top + h - foot, left + w, top + h], fill=colour)


def _canvas(size: int) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (size * SS, size * SS), TRANSPARENT)
    return img, ImageDraw.Draw(img)


def _finish(img: Image.Image, size: int, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path, "PNG", optimize=True)
    print(f"  {path}  {size}x{size}")


def tile(size: int, path: str, *, inset: float = 0.0, radius: float = TILE_RADIUS) -> None:
    """Rounded accent tile with the navy L — the mark as designed."""
    img, d = _canvas(size)
    s = size * SS
    pad = inset * s
    d.rounded_rectangle([pad, pad, s - pad, s - pad], radius=radius * s, fill=ACCENT)
    _draw_l(d, s / 2, s / 2, s - 2 * pad, BG_DEEP)
    _finish(img, size, path)


def full_bleed(size: int, path: str, *, safe: float) -> None:
    """Edge-to-edge accent ground, glyph inside ``safe`` — for maskable icons."""
    img, d = _canvas(size)
    s = size * SS
    d.rectangle([0, 0, s, s], fill=ACCENT)
    _draw_l(d, s / 2, s / 2, s * safe, BG_DEEP)
    _finish(img, size, path)


def foreground(size: int, path: str) -> None:
    """Adaptive-icon foreground: glyph only, transparent ground.

    Android composites this over the background layer on a 108dp canvas of
    which only the centre 72dp is guaranteed visible, so the glyph is scaled
    by 72/108 to land at the same optical size as the legacy tile.
    """
    img, d = _canvas(size)
    s = size * SS
    # Navy, NOT accent: the background layer this composites over is
    # ``ic_launcher_background`` = accent, so an accent glyph is invisible on
    # every API-26+ device while the legacy tile beside it looks correct.
    _draw_l(d, s / 2, s / 2, s * (72 / 108), BG_DEEP)
    _finish(img, size, path)


def mono(size: int, path: str) -> None:
    """Android 13 themed-icon layer: the glyph as a pure alpha mask.

    The platform tints this with the user's wallpaper colours, so it must be
    a single flat shape — white here, alpha is what carries the shape.
    """
    img, d = _canvas(size)
    s = size * SS
    _draw_l(d, s / 2, s / 2, s * (72 / 108), (255, 255, 255, 255))
    _finish(img, size, path)


# Android density buckets, as multiples of the mdpi baseline.
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

RES = "assets/brand/android/res"
WEB = "web"


def main() -> None:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)

    print("Android launcher (legacy, pre-API-26):")
    for bucket, mult in DENSITIES.items():
        tile(int(48 * mult), f"{RES}/mipmap-{bucket}/ic_launcher.png")

    print("Android adaptive foreground + monochrome (API 26+ / 33+):")
    for bucket, mult in DENSITIES.items():
        foreground(int(108 * mult), f"{RES}/mipmap-{bucket}/ic_launcher_foreground.png")
        mono(int(108 * mult), f"{RES}/mipmap-{bucket}/ic_launcher_monochrome.png")

    print("Android splash mark (centred on the navy launch background):")
    for bucket, mult in DENSITIES.items():
        tile(int(160 * mult), f"{RES}/mipmap-{bucket}/ic_launcher_splash.png")

    print("Play Console listing icon (uploaded by hand, not bundled):")
    tile(512, "assets/brand/play_store_512.png")

    print("Web / PWA:")
    tile(192, f"{WEB}/icons/Icon-192.png")
    tile(512, f"{WEB}/icons/Icon-512.png")
    # Maskable safe zone is the centre 80% of the canvas (W3C minimum).
    full_bleed(192, f"{WEB}/icons/Icon-maskable-192.png", safe=0.8)
    full_bleed(512, f"{WEB}/icons/Icon-maskable-512.png", safe=0.8)
    # Favicons render at 16px, where a 22% corner radius reads as mush.
    tile(32, f"{WEB}/favicon.png", radius=0.14)

    print("\nDone.")


if __name__ == "__main__":
    main()
