---
title: 0002. Version the standard with SemVer through release-please
description: The standard is released with tags and a changelog, and SemVer levels are defined by their effect on repositories that follow it.
type: explanation
audience: [developer]
status: accepted
date: 2026-11-16
---

# 0002. Version the standard with SemVer through release-please

Status: accepted (2026-11-16).

## Context

STANDARD.md carried a hand-written version line, but the repository had no
tags and no changelog. Repositories that follow the standard could not record
which version they follow, and there was no fixed point to compare against
when the standard changed. Tools that carry template changes into existing
repositories, such as Copier and Renovate, key their updates on tags.

The standard is also unlike a library. Its "users" are repositories, and a
change can break them in ways a function signature cannot show: a new
required check can turn a green repository red without any change to its
code.

## Decision

repo-standard is released like the repositories it governs. release-please
reads the Conventional Commits on `main`, keeps one release PR open, and on
merge tags `vX.Y.Z`, writes `CHANGELOG.md`, and rewrites the version line in
STANDARD.md through a generic `extra-files` entry (the `simple` release
type also keeps a root `version.txt`). The manifest starts at 1.3.0, the
version STANDARD.md stated when this decision was made, which took effect
with the Windows support merge (#18, 2026-11-17). `bootstrap-sha` points
there and keeps earlier history out of the first changelog. Tagging that
commit `v1.3.0` lets tools compare against 1.3.0 too.

A change is versioned by its effect on a repository that already follows the
standard:

- **Major** (any type with `!`, such as `feat!` or `fix!`, or a
  `BREAKING CHANGE:` footer): an existing, compliant
  repository fails a required check, or must change files or settings by
  hand, after updating. Examples: a new required CI job, a stricter hook that
  rejects existing content, a renamed or removed script option.
- **Minor** (`feat`): something new that a repository can adopt or that only
  applies to new repositories: a new overlay or add-on, a new optional check,
  a new script, a new recommended practice.
- **Patch** (`fix`, `perf`, `revert`): a correction that keeps behavior for
  compliant repositories: a bug fix in a script, a corrected statement, a pin
  update.

STANDARD.md is the product, so a change to one of its rules is `feat` (a new
or stricter rule) or `fix` (a corrected one), never `docs`. Changes of the
other types (`docs` for wording, `refactor`, `test`, `build`, `ci`, `chore`)
do not release on their own and are left out of the changelog.

## Consequences

- A repository can record the version it follows (the stamp, a separate
  change), and tooling can compare a repository against the version it
  claims.
- The changelog is the upgrade guide. A major release's `BREAKING CHANGE:`
  footer must say what a repository has to do.
- Tags only appear once the release App is installed on repo-standard and its
  client id variable and private key secret are set; until then the release
  workflow reports "not configured" and succeeds.
- Contributors have to judge the version level by downstream effect, not by
  the size of the diff. A one-line hook change can be major.
