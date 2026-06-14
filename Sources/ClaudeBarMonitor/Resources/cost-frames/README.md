# cost-frames

Pixel engineer animation for the **session-cost** face of the Touch Bar item.

The Control Strip shows a *single* item with two faces: the 5h usage gauge and
the session cost. Tapping toggles between them (a second Control Strip item is
not possible — it replaces the first rather than sitting beside it). On the cost
face, `CostRenderer` bakes the engineer frame plus the objective cost
(e.g. `$3.42`) into one image so the text never truncates.

Drop an animated GIF named `engineer.gif` here. It is loaded by
`TokenAnimation.loadFrames(directory: "cost-frames", gifName: "engineer.gif")`
and its frames are cycled at 10fps.

Until `engineer.gif` is present, the cost face falls back to the existing
`token-frames/token.gif` so it is never blank during the demo.

GIF frames should already be separate and transparent (no slicing or
white-knockout is applied to the GIF path).
