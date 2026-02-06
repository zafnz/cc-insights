
### Check if a branch can merge cleanly:

```
cd $REPO_ROOT && git merge --no-commit --no-ff $BRANCH 2>&1; MERGE_RESULT=$?; git merge --abort 2>/dev/null; exit $MERGE_RESULT
```

## Terms
- **<base>**: What this branch was based off, often origin/main or local main. 

## Are my commits on base (remote or local)
git fetch
git merge-base --is-ancestor <branch> <base>

## With squash commits

git cherry <base> <branch>
^^ if any line starts with + then its not fully merged.

