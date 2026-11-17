---
title: 0005. ASCII source, Unicode prose, no invisible characters
description: Code and config stay ASCII, prose and fixtures may use Unicode, and bidirectional or zero-width characters are rejected everywhere.
type: explanation
audience: [developer]
status: accepted
date: 2026-11-17
---

# 0005. ASCII source, Unicode prose, no invisible characters

Status: accepted (2026-11-17).

## Context

The `ascii-only` hook rejected every non-ASCII byte in every text file. That
kept source code free of look-alike characters, but it also rejected
ordinary text: a contributor's name in the docs, a translation file, or a
fixture that tests a non-English value. Repositories with translations
could not adopt the standard without excluding the hook.

The real risk is narrower and not limited to code. Bidirectional control
characters and zero-width characters (CVE-2021-42574, "Trojan Source")
make text display differently from what a compiler, interpreter or
reviewer's tooling reads, and they can hide in Markdown just as well.

## Decision

- `ascii-only` keeps checking code and config, and skips prose (`.md`,
  `.mdx`, `.txt`, `.rst`), translations (`locales/`, `i18n/`,
  `translations/`, `.po`, `.pot`, `.xlf`), tabular test data (`.csv`,
  `.tsv`) and `fixtures/` folders.
- A new `no-invisible-unicode` hook rejects, in every text file, the
  bidirectional controls `U+202A` to `U+202E` and `U+2066` to `U+2069`, the
  zero-width and direction marks `U+200B` to `U+200F` and `U+2060` to
  `U+2064`, and the byte order mark `U+FEFF`.

## Consequences

- Docs and translations can use real names and languages.
- Hidden-character attacks are blocked in prose as well as code, which the
  old rule did not state as a goal.
- A source file still cannot hold a literal non-ASCII string; tests build
  such values from escapes.
