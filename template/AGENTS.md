# Agent instructions

Instructions for coding agents in this repository. Claude Code reads this
file through `CLAUDE.md`; Codex, Copilot, Cursor, Gemini CLI and others read
it directly. The repository follows the
[repo standard](https://github.com/__OWNER__/repo-standard/blob/main/STANDARD.md);
every rule an agent needs is repeated here, so the link is background.

## Workflow

- Never push to `main`, and never use `--no-verify`. Work on a branch named
  `<type>/<issue>-<slug>` (for example `feat/12-csv-export`; omit the issue
  number when there is none) and land it through a squash-merged pull
  request.
- Features and bugs start from an issue; chores and docs may skip it.
- Keep a pull request small: about 100 changed lines, split past 400.
  Refactors go in their own pull request.
- Fill in every section of the pull request template. A pull request
  with an empty testing section is not ready.
- Run a code review on the full diff, address the findings, and post a short
  summary comment before asking for a merge.
- Ask the maintainer before merging any pull request, including release
  and Dependabot pull requests: merging the release pull request is a
  release.
- Keep the `ci` and `pr-title` checks green. Never weaken, skip, or delete a
  check to make it pass.

## Commits and pull requests

- Conventional Commits: `type(scope): subject`, imperative mood, lowercase
  first letter, no trailing period, at most 72 characters. Types: `feat`,
  `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`, `chore`,
  `revert`.
- A body explains why the change is needed, the approach, and any
  trade-offs. Wrap it at 72 columns.
- Breaking changes: `!` after the type or scope, plus a `BREAKING CHANGE:`
  footer that says how to migrate.
- The pull request title follows the same format; the squash commit takes
  the title as its subject and the body as its message.
- No AI attribution: no `Co-Authored-By` lines naming an AI tool and no
  "Generated with" footers, in commits or in pull request bodies. A hook and
  the `pr-title` check reject them. The repository states once, in
  `CONTRIBUTING.md`, that it is developed with AI coding agents.
- Never edit `CHANGELOG.md`; release-please writes it.

## Files and content

- Source code lives in the language layout's source folder, never at the
  repository root.
- Source files are English and plain ASCII only. Build any non-ASCII test
  value from escapes.
- No secrets, credentials, real personal data, or large binaries in the
  tree. Do not read `.env` files or private keys.
- Plans, research, session notes and drafts go in `.scratch/`, which is
  gitignored. A hook rejects files named like plans or notes anywhere else.
- Final design decisions go in `docs/dev/adr/` as numbered decision
  records. Documentation follows the Diataxis folders in `docs/` and ships
  in the same pull request as the behavior it describes.

## Before the first change

If `docs/dev/` does not yet record this repository's adjustments, ask the
maintainer and record the answers:

- visibility, license, and any required file headers;
- sensitive data rules (for example health data): no real data in fixtures,
  logs, issues, or prompts, and the `sensitive-data` add-on for health or
  other personal data;
- contribution rules from a client or collaborator;
- whether the repository publishes a docs site, and from which trigger;
- whether the maintainer has admin rights (without them, change files and
  hooks only, never repository settings).

## Commands

Install the hooks once per clone, then run every check CI runs:

```bash
pre-commit install
pre-commit run --all-files
```

<!-- LANGUAGE COMMANDS (added by overlay) -->
