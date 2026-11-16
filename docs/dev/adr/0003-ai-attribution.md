---
title: 0003. Disclose AI use per repository, not per commit
description: Commits and PR bodies carry no AI attribution lines; each repository states once that it is built with AI coding agents.
type: explanation
audience: [developer]
status: accepted
date: 2026-11-16
---

# 0003. Disclose AI use per repository, not per commit

Status: accepted (2026-11-16).

## Context

Nearly every change in the owner's repositories is written with an AI coding
agent and reviewed by the maintainer. Agents add attribution by default:
Claude Code appends a `Co-Authored-By` trailer and a "Generated with" footer
unless its `attribution` setting is empty.

A survey of published policies (November 2026) found three positions on
AI-assisted contributions to other people's projects: bans (Gentoo, NetBSD,
QEMU), required or requested disclosure (the Linux kernel's
`Assisted-by:` trailer, Ghostty, Fedora, LLVM, Apache's `Generated-by:`),
and "the contributor is responsible" without a disclosure rule (CPython,
Mozilla). LLVM notes that `Co-Authored-By` for a tool is not a policy
convention. None of the policies asks a maintainer to tag their own commits
in their own repository.

## Decision

- Commits and PR bodies carry no AI attribution lines: no
  `Co-Authored-By` naming an AI tool and no "Generated with" footers.
- Each repository states once, in `CONTRIBUTING.md`, that it is developed
  with AI coding agents and that the maintainer reviews every change.
- Contributions made with AI help are welcome when the contributor
  understands every line, discloses significant AI use in the PR
  description in plain words, and does not submit unreviewed changes from an
  autonomous agent.
- Contributions to other projects follow that project's policy, including
  an `Assisted-by:` trailer where it is asked for.
- Enforcement is layered: empty `attribution` strings in the committed
  `.claude/settings.json`, the `no-ai-attribution` commit-msg hook, and a PR
  body check in the required `pr-title` job.

## Consequences

- The disclosure is honest and visible without repeating the same trailer
  on every commit, where it would carry no information.
- The history stays readable, and `git log` and the changelog show only
  human-meaningful trailers such as `Fixes #N` and `BREAKING CHANGE:`.
- If disclosure per commit becomes expected (for example a platform or a
  client requires it), switch to `Assisted-by: <tool>:<model>` and change
  the hook and the `pr-title` check to allow it. The hook pattern already
  leaves `Assisted-by:` alone.
- Human co-authors still use `Co-Authored-By` as before.
