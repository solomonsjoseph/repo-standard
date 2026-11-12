---
title: 0001. Adopt a hybrid big-tech repository standard
description: Use one Conventional Commits, main-only, release-please standard for every repository.
type: explanation
audience: [developer]
status: accepted
date: 2026-11-12
---

# 0001. Adopt a hybrid big-tech repository standard

Status: accepted (2026-11-12).

## Context

Repositories on both accounts had no common layout, commit format, review
gate or release process. Research covered Google (Angular, Kubernetes, Go,
eng-practices), Microsoft (VS Code, TypeScript, Release Flow), Meta (React),
AWS CDK, GitHub's own guidance, DORA, and OpenSSF. No single company uses one
pattern; the useful unit is an archetype.

## Decision

Use the Conventional Commits archetype (Angular, AWS CDK) with main-only
trunk-based branching, squash-merged PRs from a fixed template, release-please
with a GitHub App token, a `main` ruleset requiring only the aggregate `ci`
check and `pr-title`, and the GitHub and OpenSSF security baseline sized for a
solo maintainer. A `develop` branch was rejected: GitHub flow, GitFlow's own
author, Atlassian, DORA and Microsoft all favor trunk-based work, and a
`develop` branch conflicts with squash merges, linear history and
commit-based changelogs. The release PR provides the buffer `develop` would.

## Consequences

Every repo looks and behaves the same, releases and changelogs are automatic,
and Claude can audit and retrofit repos mechanically. Costs: a one-time GitHub
App setup per account, an App key secret per repo, and required approvals are
impossible solo, so the AI review and self-review are process rules rather
than server-enforced.
