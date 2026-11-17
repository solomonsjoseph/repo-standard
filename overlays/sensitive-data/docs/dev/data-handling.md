---
title: Data handling
description: Where this repository's sensitive data may and may not go, and what checks enforce it.
type: explanation
audience: [developer]
---

# Data handling

This repository works with protected health information (PHI) or other
personal data. The rule is simple: **data never enters git, GitHub, or an AI
tool that is not covered by an agreement for it.** The repository holds code,
schemas and synthetic test data only.

## Where data may go

| Place | Real data | Why |
|---|---|---|
| Git history, branches, tags | Never | History is copied to every clone and is hard to erase |
| GitHub (issues, pull requests, Actions logs and artifacts, Codespaces) | Never | GitHub offers no business associate agreement (BAA) on its plans, and its data protection agreement excludes PHI |
| AI coding tools (Claude Code, Copilot, others) | Never, unless the account is covered by a BAA and configured for it | Consumer and team plans are not covered; check the vendor's current BAA scope before relying on it |
| The gitignored `data/` folder, or storage outside the repository | Yes, under the data owner's rules | Stays on approved machines |
| `tests/fixtures/synthetic/` | Synthetic only | Committed and visible to everyone with access |

## Synthetic test data

- Generate it with code and a fixed seed, so a test failure can be
  reproduced. Commit the generator next to the fixtures.
- Keep the shape of the real data (columns, types, missing values, edge
  cases), not its values.
- No real or realistic identifiers: no SSNs, medical record numbers, full
  dates of birth, five-digit ZIP codes or ages over 89. A hashed or encrypted
  real identifier still counts as derived from the person (45 CFR
  164.514(c)).
- When a test needs an identifier, use a format no real record has: SSNs in
  the never-issued 900 to 999 range, record numbers with a `SYN-` prefix
  and letters (`SYN-TEST-A`), and birth years only. The gitleaks rules scan
  the fixtures too and reject anything that looks real.

An R package in this repository does not ship datasets in `data/`: the
root `data/` folder is reserved for real data and is gitignored, and the
`no-data-files` hook blocks `.rda` files. Build examples from the synthetic
fixtures instead.

## What the checks enforce

| Check | Where | What it catches |
|---|---|---|
| `no-data-files` hook | pre-commit and CI | Data file types (CSV, Parquet, Excel, SAS, Stata, SPSS, R data, SQLite, DICOM and others) anywhere except `tests/fixtures/synthetic/` |
| gitleaks with `.gitleaks.toml` | pre-commit and the CI `secrets` job | Every default secret rule, plus SSNs and labeled medical record numbers and dates of birth, in every file including fixtures |
| `.gitignore` | git | The root `data/`, `raw/`, `_targets/` and `_freeze/` folders, R session files, and the binary data formats the deny rules list (except in `tests/fixtures/synthetic/`) |
| `.claude/settings.json` deny rules | Claude Code | Reads of `data/`, `raw/`, `_targets/` and binary data formats (SAS, Stata, SPSS, R, Parquet, Feather, Excel); CSV stays readable so agents can use the synthetic fixtures |

These checks catch mistakes; they do not prove that data is absent. The
Claude Code deny rules stop the Read tool only: a shell command can still
print a file, so the rule in `AGENTS.md` matters more than the setting.
Pattern rules miss identifiers that look like ordinary numbers, and free
text can identify a person without any identifier at all.

## If data reaches the repository

1. Stop. Do not push, or if it is pushed, do not open more pull requests
   that copy it.
2. Tell the maintainer and the data owner. Report it under your
   organization's incident process; a disclosure may need to be reported.
3. The maintainer removes it from history (for example with
   `git filter-repo`), force-pushes once with the owner's approval, and asks
   GitHub Support to purge cached views. Every clone must be deleted and
   cloned again.
