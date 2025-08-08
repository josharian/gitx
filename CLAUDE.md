This is a project to resuscitate GitX.

* [x] make it compile
* [x] replace objective-git with git exec
* [x] debug obvious issues (visual, functional)
* [ ] incrementally migrate to Swift

The last commit before starting surgery has the git tag 'before-revival'.

When a set of fixes is ready, please ask the user to quit their current GitX. Then clean, rebuild, and launch the app for testing.

If you need to instrument the app:

- use a distinctive substring (the app logs a lot)
- run `log stream` in the background with a long timeout with appropriate filters, e.g. 'process == "GitX" AND eventMessage CONTAINS "DISTINCTIVE_SUBSTRING"'
- launch the app
- if necessary to reproduce, ask me to take appropriate reproduction steps

NEVER leave behind breadcrumbs, backwards compatibility shims, dead code, or comments about how the code used to be. Make the code clean, as if someone was reading it for the first time ever after your work.
