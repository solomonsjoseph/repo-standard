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
STANDARD.md through a generic `extra-files` entry. The manifest starts at
1.3.0, the version STANDARD.md stated when this decision was made, and
`bootstrap-sha` keeps earlier history out of the first changelog.

A change is versioned by its effect on a repository that already follows the
standard:

- **Major** (`feat!` or `BREAKING CHANGE:`): an existing, compliant
  repository fails a required check, or must change files or settings by
  hand, after updating. Examples: a new required CI job, a stricter hook that
  rejects existing content, a renamed or removed script option.
- **Minor** (`feat`): something new that a repository can adopt or that only
  applies to new repositories: a new overlay or add-on, a new optional check,
  a new script, a new recommended practice.
- **Patch** (`fix`): a correction that keeps behavior for compliant
  repositories: a bug fix in a script, a corrected statement, a pin update.

Documentation-only changes (`docs`) do not release on their own; they ship
with the next release that does.

## Consequences

- Every repository can record the version it follows, and later tooling can
  compare a repository against the version it claims.
- The changelog is the upgrade guide. A major release's `BREAKING CHANGE:`
  footer must say what a repository has to do.
- Tags only appear once the release App is installed on repo-standard and its
  client id variable and private key secret are set; until then the release
  workflow reports "not configured" and succeeds.
- Contributors have to judge the version level by downstream effect, not by
  the size of the diff. A one-line hook change can be major.
