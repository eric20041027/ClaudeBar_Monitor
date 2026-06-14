# cost-frames

Pixel engineer animation for the **session-cost** face of the Touch Bar item.

The Control Strip shows a *single* item with two faces: the 5h usage gauge and
the session cost. Tapping toggles between them (a second Control Strip item is
not possible — it replaces the first rather than sitting beside it). On the cost
face, `CostRenderer` bakes the engineer frame plus the objective cost
(e.g. `$3.42`) into one image so the text never truncates.

## Per-level engineer GIFs

The cost face swaps the engineer animation by cost level, matching the
`CostDisplay` thresholds (`busyThreshold` / `hotThreshold`):

| Level  | GIF         | Mood                          |
| ------ | ----------- | ----------------------------- |
| `calm` | `calm.gif`  | relaxed, hands on the laptop  |
| `busy` | `busy.gif`  | leaning in, focused typing    |
| `hot`  | `hot.gif`   | head-in-hands panic           |

### Source art

These are built from the **pixellab "Engineer Calm"** character group, **south**
(front-facing) rotation so the face and pose read clearly on the Touch Bar. The
source stills live in `assets/pixellab-engineer-south/`. pixellab only produced
a real animation for the side (east) direction, so the front stills are animated
*procedurally* — a small per-state motion (calm breathing bob / busy typing
jitter / hot nervous shake) — by `scripts/gen_engineer_gifs_pixellab.py`, which
also union-bbox crops each set to FILL the canvas (see the Touch Bar shrink note
below). Re-run that script to regenerate. (The earlier hand-drawn Pillow set
came from `scripts/gen_engineer_gifs.py`, kept for reference.)

Each is loaded by
`TokenAnimation.loadFrames(directory: "cost-frames", gifName: level.gifName)`
and `TouchBarController` cycles the current level's frames at 10fps,
re-resolving the level whenever the cost updates.

### Fallback chain

Any missing per-level GIF resolves to a shared fallback, checked in order:

1. `engineer.gif` in this folder (single all-purpose engineer), then
2. `token-frames/token.gif` (the gauge coin),

so the cost face is never blank — the build and run work even with no GIFs
bundled here.

GIF frames should already be separate and transparent (no slicing or
white-knockout is applied to the GIF path).
