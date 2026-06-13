# Token animation frames

Drop the centre-icon animation frames here. `TokenAnimation.loadFrames()`
loads them at startup and `TouchBarController` cycles them at 10 fps inside the
gauge ring. Two layouts are supported:

## Option A — numbered PNG frames (preferred)

Individual transparent PNGs with a trailing integer; sorted by that integer:

```
token-00.png
token-01.png
token-02.png
...
```

## Option B — single sprite sheet

One `token-sheet.png` laid out left-to-right in a single row. Add a sidecar to
declare the frame count (otherwise square frames are assumed):

```
token-sheet.png
token-sheet.json   →  { "frames": 8 }
```

If no frames are present, the app falls back to a `🤖 NN%` text label, so the
build and run still work without this asset.
