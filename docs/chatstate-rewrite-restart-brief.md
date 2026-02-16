# ChatState Rewrite Restart Brief

Use this prompt when restarting Codex in this worktree:

```text
Work in /Users/zaf/projects/.cc-insights-wt/cci/chatstate-rewrite-codex.

Primary plan:
- docs/chatstate-rewrite-proposal-2.md

Execution docs:
- docs/chatstate-rewrite-execution.md
- docs/chatstate-rewrite-test-strategy.md

Task:
1. Read proposal-2 and execution tracker.
2. Create/update a concrete inventory of current ChatState references in frontend/lib and frontend/test.
3. Start Chunk A only (sub-state skeletons + compatibility facade scaffolding), no provider migration yet.
4. Add/adjust tests needed for Chunk A.
5. Run relevant tests with ./frontend/run-flutter-test.sh.
6. Update docs/chatstate-rewrite-execution.md with status, files touched, tests run, and outcomes.

Constraints:
- Do not start Chunk B.
- Preserve existing runtime behavior.
- Keep changes commit-sized and atomic.
```

