#!/usr/bin/env python3
"""Generate the three pixel-engineer cost GIFs (calm / busy / hot).

Hand-authored pixel art via Pillow so it needs no external art service or
Aseprite full version. Each GIF is transparent, square, and cycles a short
loop at the controller's 10fps. Output lands in
``Sources/ClaudeBarMonitor/Resources/cost-frames/`` as ``calm.gif``,
``busy.gif`` and ``hot.gif`` — the filenames ``CostLevel.gifName`` expects.

The engineer is a side-view chibi at a laptop, drawn on a GRID-px grid then
nearest-neighbour upscaled so it stays crisp. The three states share the same
body/desk so only the mood (arms, sweat, shake) differs, matching the
calm->busy->hot cost progression.
"""

from __future__ import annotations

import os
from PIL import Image, ImageDraw

# Logical pixel grid; the canvas is GRID*SCALE px so frames are chunky pixel art.
GRID = 34
SCALE = 6
CANVAS = GRID * SCALE
FRAME_MS = 100  # 10fps to match TouchBarController.animationFPS

OUT_DIR = os.path.join(
    os.path.dirname(__file__), "..",
    "Sources", "ClaudeBarMonitor", "Resources", "cost-frames",
)

TRANSPARENT = (0, 0, 0, 0)

# Palette — hoodie engineer with headphones, warm skin, dark laptop.
SKIN = (242, 198, 161, 255)
SKIN_SH = (214, 165, 128, 255)
HAIR = (60, 47, 47, 255)
HOODIE = (74, 110, 162, 255)      # calm blue
HOODIE_SH = (52, 80, 122, 255)
OUTLINE = (28, 24, 30, 255)
HEADPHONE = (40, 40, 46, 255)
LAPTOP = (54, 58, 68, 255)
LAPTOP_LID = (74, 80, 92, 255)
SCREEN = (150, 220, 255, 255)
SWEAT = (120, 205, 255, 255)
DESK = (96, 74, 58, 255)


def _grid_image() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (GRID, GRID), TRANSPARENT)
    return img, ImageDraw.Draw(img)


def px(d: ImageDraw.ImageDraw, x: int, y: int, color) -> None:
    """Set a single logical pixel (bounds-checked)."""
    if 0 <= x < GRID and 0 <= y < GRID:
        d.point((x, y), fill=color)


def rect(d, x0, y0, x1, y1, color) -> None:
    d.rectangle([x0, y0, x1, y1], fill=color)


def draw_desk(d) -> None:
    """Shared desk + laptop base along the bottom."""
    rect(d, 4, 28, 30, 30, DESK)
    rect(d, 4, 31, 30, 31, OUTLINE)
    # Laptop base (keyboard deck) and raised lid with a glowing screen.
    rect(d, 18, 24, 28, 27, LAPTOP)
    rect(d, 18, 27, 28, 27, OUTLINE)
    rect(d, 19, 14, 28, 24, OUTLINE)        # lid outline
    rect(d, 20, 15, 27, 23, LAPTOP_LID)
    rect(d, 21, 16, 26, 22, SCREEN)


def draw_body(d, lean: int = 0) -> None:
    """Shared head + hoodie torso. `lean` shifts the upper body forward."""
    lx = lean
    # Hoodie torso.
    rect(d, 8 + lx, 19, 18 + lx, 28, HOODIE)
    rect(d, 8 + lx, 19, 8 + lx, 28, HOODIE_SH)
    rect(d, 7 + lx, 19, 7 + lx, 28, OUTLINE)
    rect(d, 19 + lx, 19, 19 + lx, 28, OUTLINE)
    # Hood bump behind the neck.
    rect(d, 9 + lx, 17, 16 + lx, 19, HOODIE_SH)
    # Head.
    rect(d, 9 + lx, 7, 18 + lx, 16, SKIN)
    rect(d, 9 + lx, 7, 9 + lx, 16, SKIN_SH)
    rect(d, 8 + lx, 6, 19 + lx, 6, OUTLINE)   # top
    rect(d, 8 + lx, 7, 8 + lx, 16, OUTLINE)   # left
    rect(d, 19 + lx, 7, 19 + lx, 16, OUTLINE)  # right
    rect(d, 9 + lx, 17, 18 + lx, 17, OUTLINE)  # chin
    # Hair sweeping back.
    rect(d, 9 + lx, 7, 18 + lx, 9, HAIR)
    rect(d, 17 + lx, 7, 18 + lx, 12, HAIR)
    # Headphone cup + band.
    rect(d, 8 + lx, 10, 9 + lx, 14, HEADPHONE)
    rect(d, 9 + lx, 5, 17 + lx, 6, HEADPHONE)
    # Eye + slight smile (mood overrides this for hot).
    px(d, 15 + lx, 12, OUTLINE)
    px(d, 16 + lx, 12, OUTLINE)


def draw_arm(d, hand_y: int, lean: int = 0) -> None:
    """Forearm reaching to the laptop deck; `hand_y` animates the typing bob."""
    lx = lean
    rect(d, 16 + lx, 21, 21 + lx, 22, HOODIE)
    rect(d, 16 + lx, 23, 21 + lx, 23, HOODIE_SH)
    # Hand on the keys.
    rect(d, 21 + lx, hand_y, 23 + lx, hand_y + 1, SKIN)
    px(d, 23 + lx, hand_y, OUTLINE)


def draw_sweat(d, drops) -> None:
    for (x, y) in drops:
        px(d, x, y, OUTLINE)
        px(d, x, y - 1, SWEAT)


def upscale(img: Image.Image) -> Image.Image:
    return img.resize((CANVAS, CANVAS), Image.NEAREST)


# ---- State builders: each returns a list of logical-grid frames. ----

def frames_calm() -> list[Image.Image]:
    """Leisurely typing: hand bobs gently, no sweat."""
    out = []
    for hand_y in (24, 23, 24, 25):
        img, d = _grid_image()
        draw_desk(d)
        draw_body(d, lean=0)
        draw_arm(d, hand_y, lean=0)
        out.append(img)
    return out


def frames_busy() -> list[Image.Image]:
    """Fast typing: bigger hand swing, leaning in, a sweat drop appears."""
    poses = [(22, []), (25, [(11, 9)]), (22, []), (25, [(11, 10)])]
    out = []
    for hand_y, drops in poses:
        img, d = _grid_image()
        draw_desk(d)
        draw_body(d, lean=1)
        draw_arm(d, hand_y, lean=1)
        draw_sweat(d, drops)
        out.append(img)
    return out


def frames_hot() -> list[Image.Image]:
    """Panic: both hands grip head, body shakes, lots of sweat."""
    out = []
    for shake, drops in ((0, [(7, 10), (20, 11)]),
                         (1, [(6, 12), (21, 9)]),
                         (-1, [(7, 9), (20, 12)]),
                         (1, [(6, 10), (21, 11)])):
        img, d = _grid_image()
        draw_desk(d)
        draw_body(d, lean=shake)
        # Worried mouth (override the smile area).
        px(d, 15 + shake, 14, OUTLINE)
        px(d, 16 + shake, 14, OUTLINE)
        # Both arms up gripping the head.
        rect(d, 7 + shake, 12, 9 + shake, 18, HOODIE)
        rect(d, 18 + shake, 12, 20 + shake, 18, HOODIE)
        rect(d, 7 + shake, 11, 9 + shake, 11, SKIN)   # left hand
        rect(d, 18 + shake, 11, 20 + shake, 11, SKIN)  # right hand
        draw_sweat(d, drops)
        out.append(img)
    return out


def save_gif(frames: list[Image.Image], name: str) -> str:
    big = [upscale(f) for f in frames]
    path = os.path.abspath(os.path.join(OUT_DIR, name))
    big[0].save(
        path, save_all=True, append_images=big[1:], duration=FRAME_MS,
        loop=0, disposal=2, transparency=0, optimize=False,
    )
    return path


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for builder, name in ((frames_calm, "calm.gif"),
                          (frames_busy, "busy.gif"),
                          (frames_hot, "hot.gif")):
        p = save_gif(builder(), name)
        with Image.open(p) as im:
            n = getattr(im, "n_frames", 1)
        print(f"wrote {name}: {n} frames, {CANVAS}x{CANVAS} -> {p}")


if __name__ == "__main__":
    main()
