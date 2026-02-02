
### Check if a branch can merge cleanly:

```
cd $REPO_ROOT && git merge --no-commit --no-ff $BRANCH 2>&1; MERGE_RESULT=$?; git merge --abort 2>/dev/null; exit $MERGE_RESULT
```

### merge main into branch
```chat
You are on a work tree. 

Your task is to merge the worktree main into this branch (not origin). If there are any merge conflicts you are to stop and ask the user what to do. Offer the options of "Automatically resolve conficts", "Wait for user to resolve", "Abort merge".

If the user selects Automatically then you are to resolve the merge conflicts as best as you can, and if you are aware of any unit tests you can run, to run them.

If you have issues merging, it is not clear what to do, or the unit tests fails, STOP and advise the user what the situation is.

Once you have finished, respond FINISHED
```