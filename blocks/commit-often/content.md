## Commit as you go

- Commit at every point where the work is in a good state, and before starting
  anything risky. An uncommitted hour is an hour that can't be recovered.
- Stage the files you meant to change, by name. Never `git add -A`, `--all` or
  `.` - they sweep in whatever else happens to be in the tree.
- Never force-push, and never rewrite a commit that has already been pushed.
  Add a new commit on top instead.
