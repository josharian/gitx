list of things i want to improve

- the discard hunk button is too small for its text. please make it a bit bigger
- add a new search bar next to the top right one. the behavior should be exactly the same except that instead of filtering by subject/sha/etc, it should run a pickaxe (git log -S) to figure out which commits to highlight.
- memoize the currently selected commit in graph view, keep it selected on refresh (no need to persist across restarts)
- when clicking a branch on left, highlight/flash the corresponding commit after scrolling to make it visible
- i'm still seeing an issue in which a window loads with the graph view above...not the diff view...but a gray zone. if i drag the slider up, you see the graph view and the diff view sharing the area where just the graph view should be. if you then resize the window, everything snaps back to normal. (if you resize the window _without_ moving the slider first, it doesn't fix itself.)
- editable diffs! (editable RHS, ideally)
