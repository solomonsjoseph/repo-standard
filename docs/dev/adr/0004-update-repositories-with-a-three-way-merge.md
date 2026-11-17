---
title: 0004. Update repositories with a three-way merge script
description: update-repo.sh carries new releases of the standard into existing repositories with git merge-file, instead of converting the template to Copier.
type: explanation
audience: [developer]
status: accepted
date: 2026-11-17
---

# 0004. Update repositories with a three-way merge script

Status: accepted (2026-11-17).

## Context

`apply-overlay.sh --retrofit` copies only missing files, so a change to a
file the standard already gave a repository never reaches it. Each
repository has edited some of those files (its README, its CI jobs, its
`.gitignore`), so overwriting them is not an option either.

Copier solves this problem for templates written for it. It renders the
template at the old and new versions and reapplies the project's own changes,
which amounts to a three-way merge. Adopting it would mean rewriting the
template and every overlay in Jinja, replacing the shell scripts with Copier
tasks, and requiring Python 3.11 or later on every machine. Every repository
that already follows the standard would need a one-time `copier copy` over
it.

## Decision

`scripts/update-repo.sh` performs the same merge without Copier. It reads the
version, overlay, add-ons and visibility from `.github/repo-standard.yml`
(ADR 0002), renders the standard at that version and at the target with each
version's own scripts, and merges each managed file with `git merge-file`:
the repository's copy is "ours", the old render is the base, the new render is
"theirs". It works on a branch, leaves the result uncommitted, and exits 1
when something needs a hand merge.

Copier stays on the list for a future major version of the standard, if the
template grows conditional files that shell scripts handle badly.

## Consequences

- Repositories keep their edits; only lines the standard changed move, and
  conflicts show as ordinary merge markers.
- Rendering with each version's own scripts means a change to
  `apply-overlay.sh` never makes the old render wrong. The cost is that only
  versions with `scripts/apply-overlay.sh` and the copy helper (1.3.0 and
  later) can be the base.
- Placeholders are filled with the same values on both sides, so a
  repository's own name or description never shows up as a change.
- Renovate cannot open update PRs the way its `copier` manager does. An
  agent or the owner runs the script per repository; the audit's RS-REL-03
  rule shows which repositories are behind.
