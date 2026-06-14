# cost-frames

Pixel engineer animation for the **session-cost** Touch Bar item (left of the
usage gauge).

Drop an animated GIF named `engineer.gif` here. It is loaded by
`TokenAnimation.loadFrames(directory: "cost-frames", gifName: "engineer.gif")`
and its frames are cycled at 10fps beside the objective cost text (e.g. `$3.42`).

Until `engineer.gif` is present, the cost item falls back to the existing
`token-frames/token.gif` so it is never blank during the demo.

GIF frames should already be separate and transparent (no slicing or
white-knockout is applied to the GIF path).
