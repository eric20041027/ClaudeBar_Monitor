#!/usr/bin/env python3
"""Build the three cost GIFs (calm / busy / hot) from the pixellab front-view art.

The source is the pixellab "Engineer Calm" character group, **south** rotation
(the character facing the camera so the face and pose read clearly on the Touch
Bar). pixellab only produced a real animation for the *east* (side) direction,
so the south stills here are animated *procedurally* — a small per-state motion
that matches the cost mood without re-spending pixellab generations:

* calm : gentle vertical breathing bob
* busy : quick small jitter on the upper body (typing energy)
* hot  : nervous left/right shake (panic)

The pixellab stills sit in a mostly-empty 92x92 canvas (the figure occupies
~28x46). Drawn straight, that shrinks to an unreadable coin-blob in the ~28pt
Touch Bar box — the engineer-not-showing bug. So every state's frames are
cropped to the SHARED union bounding box of that state's frames (a shared crop
so the figure doesn't jitter against the frame), then nearest-neighbour upscaled
so the engineer FILLS the GIF and stays crisp at Control Strip size.

Output overwrites ``Sources/ClaudeBarMonitor/Resources/cost-frames/{calm,busy,
hot}.gif`` — the filenames ``CostLevel.gifName`` expects. The Swift wiring and
fallback chain accept them unchanged.
"""

from __future__ import annotations

import os
from PIL import Image

SRC_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "pixellab-engineer-south")
OUT_DIR = os.path.join(
    os.path.dirname(__file__), "..",
    "Sources", "ClaudeBarMonitor", "Resources", "cost-frames",
)

FRAME_MS = 100          # 10fps to match TouchBarController.animationFPS
TARGET = 180            # longest cropped side scales up to ~this many px (crisp)
CROP_MARGIN = 2         # logical-px padding kept around the figure after crop
TRANSPARENT = (0, 0, 0, 0)


def _load(name: str) -> Image.Image:
    return Image.open(os.path.join(SRC_DIR, name)).convert("RGBA")


def _shift(img: Image.Image, dx: int, dy: int) -> Image.Image:
    """Translate the figure on a same-size transparent canvas (no wrap)."""
    out = Image.new("RGBA", img.size, TRANSPARENT)
    out.paste(img, (dx, dy), img)
    return out


def frames_calm(src: Image.Image) -> list[Image.Image]:
    """Gentle breathing: the whole figure drifts down 1px and back."""
    return [_shift(src, 0, dy) for dy in (0, 1, 1, 0)]


def frames_busy(src: Image.Image) -> list[Image.Image]:
    """Typing energy: small quick bob, alternating a 1px horizontal nudge."""
    return [
        _shift(src, 0, 0),
        _shift(src, 1, 1),
        _shift(src, 0, 0),
        _shift(src, -1, 1),
    ]


def frames_hot(src: Image.Image) -> list[Image.Image]:
    """Panic: nervous left/right shake."""
    return [_shift(src, dx, 0) for dx in (-1, 1, -1, 1)]


def union_bbox(frames: list[Image.Image]) -> tuple[int, int, int, int]:
    """Box covering opaque content of every frame, padded and clamped."""
    w, h = frames[0].size
    box: tuple[int, int, int, int] | None = None
    for f in frames:
        bb = f.getbbox()
        if bb is None:
            continue
        box = bb if box is None else (
            min(box[0], bb[0]), min(box[1], bb[1]),
            max(box[2], bb[2]), max(box[3], bb[3]),
        )
    if box is None:
        return (0, 0, w, h)
    return (
        max(0, box[0] - CROP_MARGIN),
        max(0, box[1] - CROP_MARGIN),
        min(w, box[2] + CROP_MARGIN),
        min(h, box[3] + CROP_MARGIN),
    )


def tight_crop(frames: list[Image.Image]) -> list[Image.Image]:
    bbox = union_bbox(frames)
    return [f.crop(bbox) for f in frames]


def scale_up(img: Image.Image, target: int) -> Image.Image:
    """Nearest-neighbour scale so the longest side becomes ~target px."""
    w, h = img.size
    factor = max(1, target // max(w, h))
    return img.resize((w * factor, h * factor), Image.NEAREST)


def save_gif(frames: list[Image.Image], name: str) -> str:
    cropped = tight_crop(frames)
    big = [scale_up(f, TARGET) for f in cropped]
    path = os.path.abspath(os.path.join(OUT_DIR, name))
    big[0].save(
        path, save_all=True, append_images=big[1:], duration=FRAME_MS,
        loop=0, disposal=2, transparency=0, optimize=False,
    )
    return path


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    jobs = (
        (frames_calm, "calm_south.png", "calm.gif"),
        (frames_busy, "busy_south.png", "busy.gif"),
        (frames_hot, "hot_south.png", "hot.gif"),
    )
    for builder, src_name, out_name in jobs:
        frames = builder(_load(src_name))
        p = save_gif(frames, out_name)
        with Image.open(p) as im:
            n = getattr(im, "n_frames", 1)
            size = im.size
        print(f"wrote {out_name}: {n} frames, {size[0]}x{size[1]} -> {p}")


if __name__ == "__main__":
    main()
