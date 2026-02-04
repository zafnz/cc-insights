# Worktree Branch Status Specification
**(Local-first & Remote-first compatible, no global toggle)**

## Goal
Provide a **single, consistent UI** that works for:
- Local-first workflows (merge locally, push occasionally)
- Remote-first / PR workflows (origin is source of truth)

The UI must allow users to understand **local integration state** and **remote publication state** at a glance, without switching modes or toggles.

---

## Core Concepts

Each branch/worktree row displays **two independent badges**:

1. **Base Badge** → *integration / merge target*
2. **Sync Badge** → *publication / upstream state*

Each badge has a **fixed meaning**.
Only the **comparison target** changes based on branch state.

---

## Badge 1: Base (Integration State)

### Question answered
> "How far is this branch from the branch it should be merged into?"

### Visual Format
```
[ 🏠 +X −Y ]   or   [ 🌐 +X −Y ]
```
### Base Markers
| Marker | Meaning |
|------|---------|
| 🏠 | Local base (local merge target) |
| 🌐 | Remote base (origin merge target) |

---

### Base Target Selection Rules (no toggle)

Base target is selected **per branch** using the following deterministic rules:

1. **If the branch has an upstream (`@{u}` exists)**
   → Use **remote base**
   - Marker: 🌐
   - Target: `refs/remotes/origin/HEAD`
     (fallback: `origin/main`, then `origin/master`)

2. **If the branch has no upstream**
   → Use **local base**
   - Marker: 🏠
   - Target: local merge target (default: `main`)

This rule allows:
- Local-only branches to behave naturally
- Published branches to match GitHub / PR reality
- No global mode or toggle

---

### Base Ahead / Behind Calculation
Use:
```
git rev-list –left-right –count BASE…HEAD
```

- `+X` = commits in branch not in base
- `−Y` = commits in base not in branch

---

### Base Badge Tooltip (required)
Tooltip must always show the exact ref.

Examples:
- `🏠 base: main`
- `🌐 base: origin/main`

---

## Badge 2: Sync (Publication State)

### Question answered
> "How far is this branch from what's published?"

### Visual Format
```
[ ☁ ↑A ↓B ]
```
### Sync Target
- Target = upstream tracking branch (`@{u}`)

---

### Sync Badge Rules
- If upstream exists:
  - Show ahead/behind vs upstream
- If no upstream:
  - Show placeholder `—`

Examples:
```
[ ☁ ↑2 ↓0 ]   // 2 commits not pushed
[ ☁ ↑0 ↓1 ]   // 1 commit to pull
[ ☁ — ]       // not published
```
---

### Sync Calculation
git rev-list –left-right –count UPSTREAM…HEAD

- `↑` = commits local has that upstream does not
- `↓` = commits upstream has that local does not

---

### Sync Tooltip (required)
Examples:
- `☁ sync: origin/my-feature`
- `☁ sync: — (no upstream)`

---

## Combined Display Examples

### Local-only feature branch
```
my-feature    [ 🏠 +3 −0 ]   [ ☁ — ]
```

### Published feature branch (PR-ready)
```
my-feature    [ 🌐 +3 −2 ]   [ ☁ ↑1 ↓0 ]
```
### Local main ahead of origin
```
main          [ 🌐 +2 −0 ]   [ ☁ ↑2 ]
```
### Branch carrying unpushed main commits
```
feature-x     [ 🌐 +5 −0 ]   [ ☁ ↑3 ]
```
(Accurately warns that branch includes commits not in `origin/main`.)

---

## UI Rules & Constraints

- **No global "Local / PR" toggle**
- Badge meanings are **stable and never change**
- Only the **base target selection is automatic**
- Tooltips must always disclose the exact ref
- Sync badge meaning is independent of base badge
- Base badge must always be shown
- Sync badge may be hidden if `—` and space is constrained (optional)

---

## Design Rationale

- 🏠 vs 🌐 communicates **source of truth**, not workflow intent
- Published branches automatically behave like PR branches
- Local-first users are never penalized for not pushing
- Remote-first users see numbers that match GitHub
- Edge cases become **useful signals**, not inconsistencies

---

## Optional Extensions (not required for v1)

- Per-repo override for local base branch name
- Per-branch pinned base target override
- Warning color when base includes unpushed local main commits
- Support multiple remotes (🌐 tooltip shows which)

---

## Non-Goals

- Detecting or displaying actual GitHub PR objects
- Inferring user intent ("about to open PR")
- Replacing `git status` or `git log`

---

## Summary

This design supports **two masters** (local and origin) by:
- Making each badge answer one clear question
- Selecting the correct comparison target automatically
- Exposing the target explicitly via emoji + tooltip

No modes. No lies. No surprises.
