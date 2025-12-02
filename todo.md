list of things i want to improve

- add a new search bar next to the top right one. the behavior should be exactly the same except that instead of filtering by subject/sha/etc, it should run a pickaxe (git log -S) to figure out which commits to highlight.
- search up/down arrows are placed weirdly, should be closer to search bar
- memoize the currently selected commit in graph view, keep it selected and scrolled into view on refresh (no need to persist across restarts)
- editable RHS in diffs!
- better copy/paste in diffs (exclude line numbers, copy only a single column's text)
- when before/after is empty, use one column for diff
