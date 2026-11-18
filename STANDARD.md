# Repo standard

Version 1.3.0 <!-- x-release-please-version -->

This is the standard every repository of the account follows. It combines
practices from Google (Angular, Kubernetes, Go, eng-practices), Microsoft
(VS Code, TypeScript, Release Flow), Meta (React), AWS (CDK), GitHub's own
guidance, DORA research, and the OpenSSF security baselines, sized for a
solo maintainer.

The standard is released like any other repository: release-please sets the
version above, tags `vX.Y.Z`, and lists the features and fixes of each
release, with their dates, in `CHANGELOG.md` (created by the first release). [ADR 0002](docs/dev/adr/0002-version-the-standard.md)
defines what counts as a major, minor, or patch change.

Words in capitals (MUST, SHOULD, MAY) follow RFC 2119.

## 1. Lifecycle at a glance

```text
idea
  -> issue (features and bugs; chores and docs may skip it)
  -> short-lived branch from main: feat/12-csv-export
  -> small commits, local hooks check each one
  -> pull request, title "feat(export): add CSV export"
  -> CI (ci + pr-title must pass), AI review, self-review checklist
  -> squash merge into main, branch deleted
  -> release-please opens or updates the release PR
  -> merging the release PR tags vX.Y.Z, writes CHANGELOG.md, creates the GitHub Release
```

## 2. Creating a repository

1. Decide the license, visibility, language overlay, any add-on overlay
   (`api-http`, `api-events`, `sensitive-data`, `citation`), whether the repo
   publishes a docs site, and
   the other per-repo adjustments (section 12).
2. Run:

   ```bash
   scripts/new-repo.sh OWNER NAME OVERLAY public|private --license SPDX|none [--addon api-http] --desc "TEXT"
   ```

   It:
   - builds the repo from `template/` in repo-standard plus the language
     overlay, any add-ons and, for public repos, the public overlay;
   - adds the license and generates lock files;
   - pushes one bootstrap commit, `chore: bootstrap from repo-standard`;
   - runs `scripts/apply-settings.sh`, which sets merge options, Actions
     permissions (SHA pinning required), security features, labels, the
     `main` ruleset, and the `release-tags` ruleset.
3. Store the release App key as a repo secret. The owner does this; Claude
   never reads the key. Keep the key in the operating system's secret store
   rather than as a file: store it once per account, then delete the
   downloaded file. Then set it for each repo.

   On macOS, use the Keychain. It returns multi-line values as hex, so store
   the key base64-encoded:

   ```bash
   security add-generic-password -s release-app-key -a OWNER -w "$(base64 < release-app.pem)"
   security find-generic-password -s release-app-key -a OWNER -w | base64 -d | gh secret set RELEASE_APP_PRIVATE_KEY --repo OWNER/NAME
   ```

   On Windows, run these in Git Bash. The key is encrypted with DPAPI, so
   only your Windows account on this machine can read it. Pipe it from
   Git Bash, not from PowerShell, because PowerShell 5.1 adds a byte-order
   mark to piped text, which breaks the key:

   ```bash
   key="$(cygpath -w ~/.config/repo-standard/release-app-key-OWNER.xml)"
   powershell.exe -NoProfile -Command "Get-Content -Raw 'release-app.pem' | ConvertTo-SecureString -AsPlainText -Force | Export-Clixml '$key'"
   powershell.exe -NoProfile -Command "[Net.NetworkCredential]::new('', (Import-Clixml '$key')).Password.TrimEnd()" | tr -d '\r' | gh secret set RELEASE_APP_PRIVATE_KEY --repo OWNER/NAME
   ```

   On Linux, use the desktop keyring through `secret-tool` (libsecret):

   ```bash
   base64 -w0 < release-app.pem | secret-tool store --label="release-app-key OWNER" service release-app-key account OWNER
   secret-tool lookup service release-app-key account OWNER | base64 -d | gh secret set RELEASE_APP_PRIVATE_KEY --repo OWNER/NAME
   ```

   Until the key, the `RELEASE_APP_CLIENT_ID` variable, and the App
   installation all exist, the release workflow reports "not configured"
   and succeeds.

4. Clone and install hooks. Install pre-commit 4.7 or later with
   `uv tool install pre-commit`: npm 12 broke node hooks in 4.6.0 and
   earlier, and 4.7.0 is the first release without the follow-on
   regressions.

   ```bash
   pre-commit install --hook-type pre-commit --hook-type commit-msg
   ```

The bootstrap commit is the only commit that goes straight to `main`.

The scripts read private per-owner settings from
`~/.config/repo-standard/OWNER.env` (display name, release App client id,
SSH signing key, and the security contact for private repos) and refuse
owners without one.

**Platforms.** The scripts are bash and run on macOS, Linux, and Windows
(in Git Bash, which Git for Windows installs). They need git, gh, perl,
jq, python3 3.9 or later, and pre-commit 4.7 or later; uv and pnpm are
needed for the python and ts overlays. Run `scripts/doctor.sh` on a new
machine. It is read-only and checks the tools, the private config, the gh
logins and, on Windows, two settings that break hooks:

- Windows Smart App Control blocks the unsigned binaries that pre-commit
  downloads or builds (Vale, gitleaks, actionlint, zizmor, and compiled
  Python extensions). Run hooks in WSL, or skip only those hooks locally with
  `SKIP=...`. CI still runs every hook, so the merge gate is unchanged.
- `core.autocrlf=true` (the Git for Windows default) is harmless inside
  standard repos, because `.gitattributes` forces LF line endings.

**Machine setup.** Run `scripts/setup-machine.sh` once per machine (and
again after updating repo-standard). It installs two guards:

- the pre-push guard (`scripts/git-hooks/pre-push`) as a git template
  hook, so every clone refuses pushes that would update or delete `main`.
  It guards repositories that follow the standard (their pre-commit config
  has the `no-commit-to-branch` hook), and allows the first push that
  creates `main`. Existing clones get it by
  running `git init` inside the clone (git keeps a pre-push hook the clone
  already has; copy the guard over it by hand there);
- the identity hook (`scripts/claude-hooks/git-identity-switch.sh`) as a
  Claude Code PreToolUse hook. Before a git command, it sets the clone's
  local commit identity and credential helper for the account that should
  act there, and blocks commits and pushes for an account with no
  `OWNER.env`. With `--act-as OWNER`, that one account acts in every
  repository, for example as a collaborator on another account's repos.

**The release App.** One private GitHub App per account, installed on all of
that account's repositories. Repository permissions: Contents read and
write, Pull requests read and write, Issues read and write (labels), and
Metadata read. Webhook off; installable only on the owning account.

**`OWNER/repo-template`** is a reference copy kept in sync by `sync.sh`.
GitHub's "Use this template" copies files only, so a repo created that way
is finished with:

```bash
scripts/finish-repo.sh OWNER/NAME OVERLAY public|private --license SPDX|none
```

It applies the overlay, placeholders, license, and settings, and opens a
`chore: finish repo-standard setup` PR.

## 3. Repository layout

Every repository has this skeleton. Language overlays add their own layout on
top (section 11).

```text
README.md                 what it is, badges, installation, quick start, usage, development, contributing, license
LICENSE                   chosen per repo
CHANGELOG.md              written by release-please, never by hand
CONTRIBUTING.md           how to propose and land a change (this standard, short form)
SECURITY.md               how to report a vulnerability privately
CODE_OF_CONDUCT.md        adopts Contributor Covenant 2.1
AGENTS.md                 instructions for coding agents; CLAUDE.md points here
.editorconfig  .gitattributes  .gitignore
.git-blame-ignore-revs    formatting-only commits that blame skips
.pre-commit-config.yaml   local hooks, also run in CI
release-please-config.json  .release-please-manifest.json
.github/
  ISSUE_TEMPLATE/         bug_report.yml, feature_request.yml, config.yml
  pull_request_template.md
  CODEOWNERS              routing only, never a required review
  dependabot.yml
  repo-standard.yml       standard version, overlay and add-ons; written by the scripts
  workflows/              ci.yml, pr-title.yml, release-please.yml, main-guard.yml
                          links.yml (weekly external link check)
                          public repos add codeql.yml, dependency-review.yml, scorecard.yml
docs/                     Diataxis layout and rules in section 15
  index.md                landing page
  tutorials/  how-to/  reference/  explanation/   created with their first page
  dev/                    contributor docs, never published
    adr/                  decision records, NNNN-short-title.md
api/                      openapi.yaml or asyncapi.yaml when the repo has an API
.vale.ini  .vale/         prose linter config, vendored Google style, project vocabulary
.lychee.toml              link checker config
.scratch/                 gitignored: plans, research, AI session notes, drafts
scripts/                  developer and maintenance scripts (includes check_docs.py)
```

Rules:

- Source code lives in the language layout's source folder, never at the root.
- Vendored third-party code lives in `third_party/<name>/` with its license.
- Generated files are not committed unless the toolchain requires it (lock
  files are committed).
- No secrets, real personal data, or large binaries in the tree.
- Source and config files are English and plain ASCII only. Build any
  non-ASCII test value from escapes. Prose (`.md`, `.mdx`, `.rst`),
  translations (`.po`, `.pot`, `.xlf`, `.xliff`), tabular data (`.csv`,
  `.tsv`), and data files (JSON, YAML, TOML, text, XML, string tables) in
  `locales/`, `i18n/`, `translations/`, `fixtures/` and `testdata/` folders
  may hold Unicode text; code in those folders stays ASCII.
- No file may contain bidirectional overrides or isolates, zero-width
  spaces or invisible operators (joiners and direction marks are allowed),
  which make code read differently from how it runs (the
  `no-invisible-unicode` hook; [ADR 0005](docs/dev/adr/0005-ascii-source-and-invisible-unicode.md)).

## 4. Branches

- `main` is the only long-lived branch. It is always releasable.
- There is no `develop` branch. The release PR is the gate between finished
  work and a release, so `main` plays the role `develop` would, and tags mark
  what shipped.
- Work branches are short-lived (hours to a few days) and named
  `<type>/<issue>-<slug>`, for example `feat/12-csv-export`,
  `fix/15-login-redirect`, `docs/readme-quickstart`. The issue number is
  omitted when there is no issue.
- A branch is deleted when its PR merges (automatic).
- `release-X.Y` branches are cut only when an old version needs support.
  Fixes land on `main` first and are cherry-picked; release branches never
  merge back.
- Long-running work stays on `main` behind a feature flag instead of on a
  long-lived branch.

## 5. Commits

Format (Conventional Commits 1.0, Angular conventions):

```text
<type>(<scope>): <subject>

<body: why the change is needed, what it does, wrapped at 72 columns>

<footer: BREAKING CHANGE: ..., Fixes #N, Refs #N>
```

- Types: `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`,
  `chore`, `revert`.
- Scope is optional and names the area or package (`auth`, `cli`, `deps`).
- Subject: imperative mood, lowercase first letter, no trailing period, at
  most 72 characters. Read it as the end of the phrase `This change`, for
  example `add CSV export`.
- Body is required for anything beyond a trivial change. It explains why,
  the approach and any trade-offs. "Fix bug" is never enough.
- Breaking change: `!` after the type or scope, plus a `BREAKING CHANGE:`
  footer describing the migration.
- A formatting-only change (a formatter run across many files) is its own
  pull request. After it merges, add the squash commit's full SHA to
  `.git-blame-ignore-revs`, so blame keeps each line's real author.
- One logical change per commit. Commits are signed with SSH when the
  owner's private config sets `SIGNING_KEY` (the key must also be added on
  GitHub as a signing key); the ruleset does not require signatures yet.
- No AI attribution lines in commits or PR bodies: no `Co-Authored-By`
  naming an AI tool and no "Generated with" footers. AI use is disclosed
  once per repository instead: `CONTRIBUTING.md` says the project is
  developed with AI coding agents and that the maintainer reviews every
  change, and sets the terms for contributions made with AI help
  (understand every line, disclose significant AI use in the PR description
  in plain words, no unreviewed autonomous-agent changes). When contributing
  to another project, follow that project's policy, for example an
  `Assisted-by:` trailer where it asks for one.
  [ADR 0003](docs/dev/adr/0003-ai-attribution.md) records why. Enforcement:
  `attribution` set to empty strings in the committed `.claude/settings.json`,
  the `no-ai-attribution` commit-msg hook, and a PR body check in the
  required `pr-title` job (the squash commit message comes from the PR
  body, which local hooks never see).

Only `feat`, `fix`, `perf` and breaking changes appear in the changelog and
bump the version: `fix` and `perf` bump the patch, `feat` the minor, a
breaking change the major (minor while below 1.0).

## 6. Pull requests

- Every change reaches `main` through a PR.
- The PR title follows the commit format, because the squash commit takes
  the PR title as its subject and the PR body as its message.
- Breaking changes use `!` in the title and a `BREAKING CHANGE:` line in the
  body.
- Keep PRs small: around 100 changed lines is ideal, past 400 split it.
  Refactors go in their own PR.
- The template sections are Summary, Why, `How I tested this`, Breaking
  change, Linked issue, and Checklist. An empty `How I tested this` section means the PR is not ready.
- Open as a draft while work is in progress.
- Link the issue with `Fixes #N` (closes it) or `Refs #N`.

## 7. Merge gate

A PR merges into `main` only when all of these hold:

| Gate | Enforced by |
|---|---|
| PR required, squash only, linear history, no force push or deletion | `main` ruleset (no bypass) |
| `ci` check green (lint, format, type check, tests, build, coverage, docs, and a gitleaks scan of the PR's commits) | ruleset required check, bound to the GitHub Actions app |
| `pr-title` check green | ruleset required check |
| Branch up to date with `main` | ruleset strict status checks |
| All review conversations resolved | ruleset |
| AI review done and findings addressed | process rule (Claude runs the code-review skill and posts a summary comment) |
| Self-review checklist ticked | process rule (PR template) |
| No open high or critical security alerts | process rule (Dependabot on every repo; CodeQL and secret scanning on public repos) |

`ci` is one aggregate job that depends on every other CI job, always runs,
and fails unless each dependency succeeded. Only `ci` and `pr-title` are
required, so a job that is skipped or never reports cannot block or silently
pass a merge.

Required approvals and required CODEOWNERS review are off: a solo maintainer
cannot approve their own PR. They are switched on the day a second
maintainer joins.

Private repos owned by a personal account on the Free plan have no rulesets
and no branch protection; GitHub Pro ($4 a month) adds both for private
repos.
There the same gate holds through CI, local hooks and the process rules, and
Claude never pushes directly to `main`. Three layers stand in for the
ruleset, and none of them is a security boundary:

| Layer | Stops | Gap |
|---|---|---|
| `no-commit-to-branch` hook | commits made on a local `main` | skipped with `--no-verify` |
| pre-push guard (machine setup) | any push that updates or deletes `main`, including commits the remote already has | skipped with `--no-verify`; only on machines that ran setup |
| `main-guard.yml` workflow | nothing; it detects after the push | fails the run and opens an issue for each push to `main` without a merged PR, and for force pushes |

### Tests

- Every bug fix adds a regression test that fails without the fix. Every
  feature ships with its tests in the same PR.
- Tests are deterministic: fixed seeds, no network, no dependence on the
  clock or on test order. A flaky test is a bug, never a retry.
- Coverage: in the python and ts overlays new repos fail under 80 percent;
  go prints its total in CI, and r and swift collect coverage without a
  floor. Retrofitted repos set their current coverage as the floor, and the
  floor only rises.
- Never lower a coverage floor, skip a test, or mark it as expected to fail
  to make a check pass.
- python runs pytest 9 in strict mode (`strict = true`), so a typo in a
  marker, an unknown config key, or an expected failure that starts
  passing fails the run.
- Parsers, serializers and data transforms get property-based tests:
  Hypothesis (python) or fast-check (ts), added as a dev dependency with the
  first such test, and native fuzz targets (go). They run deterministically
  in CI: Hypothesis with `derandomize=True` and `deadline=None`, fast-check
  with a fixed `seed`. Go fuzz targets keep their corpus in
  `testdata/fuzz/`, which `go test` runs as ordinary regression tests.
- Test data is synthetic; the `sensitive-data` add-on (section 11) adds the
  rules for repos that handle personal data.

### Bot pull requests

release-please and Dependabot PRs skip the issue-first rule, the checklist,
and the AI review, but `ci` and `pr-title` must still pass. Claude asks
before merging any of them: merging the release PR is a release.

## 8. Releases

- release-please reads the Conventional Commits on `main` and keeps one
  release PR open (`chore(main): release X.Y.Z`).
- Merging the release PR creates the `vX.Y.Z` tag (`include-component-in-tag`
  is false, so tags never carry the package name), updates `CHANGELOG.md`,
  and publishes the GitHub Release. The `release-tags` ruleset stops `v*`
  tags from being moved or deleted.
- Version files: python bumps `pyproject.toml` and `uv.lock` (an
  `extra-files` entry, so the release PR passes `uv sync --locked`), ts
  bumps `package.json`, go uses tags only, and r bumps `DESCRIPTION`.
- release-please runs with a GitHub App token (one private App per account),
  because PRs opened with the default token do not trigger CI and could never
  pass the required checks.
- Versions follow SemVer 2.0. Pre-1.0, breaking changes bump the minor.
- Repos that only deploy from `main` still keep releases: the tag records
  what was deployed.
- Retrofitted repos set `bootstrap-sha` so older, non-conventional history is
  ignored.
- Public repos that publish packages or binaries add build provenance with
  `actions/attest` (on the Free, Pro and Team plans, artifact attestations
  work for public repos only). Repos that ship binaries or container images,
  or packages that bundle or vendor their dependencies, also publish an SBOM;
  other packages installed from a registry do not need one.

## 9. Security and supply chain

- MFA on every account.
- `SECURITY.md` on every repo, and private vulnerability reporting on every
  public repo (GitHub offers it for public repos only). It states the
  response times (an answer within 7 days, progress every 14), what is in
  scope, and how a fix is released. A private repo has no reporting
  button, so its `SECURITY.md` names the owner's `SECURITY_CONTACT` when
  `OWNER.env` sets one, and the owner's profile otherwise.
- Dependabot alerts and security updates on. Version updates for every
  ecosystem in the repo, including `github-actions`, with a 7-day cooldown
  for non-security updates (GitHub's default has been 3 days since
  2026-07-14; the standard keeps the longer window, the one zizmor checks
  for). Dependabot never delays a security update; when the resolver
  cooldown below blocks one, the exception goes in the same pull request.
  Commit prefixes: `fix(deps)`
  for production dependencies, `chore(deps-dev)` for development
  dependencies.
- The package managers apply the same 7-day cooldown when they resolve:
  `exclude-newer = "1 week"` under `[tool.uv]` (python overlay) and
  `minimumReleaseAge: 10080` in `pnpm-workspace.yaml` (ts overlay; a
  settings file, not a monorepo). There `allowBuilds` decides install
  scripts: `true` runs a dependency's script, `false` blocks it, and an
  unlisted dependency with a script fails the install. A security fix
  younger than a week needs a per-package exception in the same pull
  request, `exclude-newer-package = { name = false }` for uv or a
  `minimumReleaseAgeExclude` entry for pnpm, removed once the release is a
  week old. `audit.sh` checks both settings (RS-DEP-05).
- Secret scanning with push protection (public repos; gitleaks covers private
  repos locally and in CI).
- Public repos: CodeQL (advanced setup), dependency review on PRs, and a
  weekly OpenSSF Scorecard run. Scorecard is informational; a solo repo
  always scores low on Code-Review and Contributors.
- Pinning: actions are pinned to full commit SHAs (and the repository
  setting requires it); pre-commit hook revs are frozen to SHAs and updated
  by Dependabot's `pre-commit` ecosystem; CI installs a pinned pre-commit
  and caches hook environments; SwiftLint is a pinned release with a
  checksum. Known exception: the lychee hook downloads `cargo-binstall`
  unpinned when its environment is first built (cached afterwards).
  GitHub now ranks workflow lockfiles (`.github/workflows/actions.lock`)
  above SHA pinning; the standard does not adopt them yet, because their
  availability for personal accounts is unclear and enforcing them on
  private repos needs a Team or Enterprise plan.
  In repo-standard itself, Dependabot sees only the root files;
  `scripts/sync-pins.sh` copies their pins into `template/` and
  `overlays/`, `--latest` refreshes the pins only those folders use (to the
  newest release at least 7 days old), and `check-drift.sh` fails while any
  action or hook is pinned to two different commits.
- Private repos on the Free plan have no rulesets or branch protection
  (GitHub Pro adds both), and no secret scanning, push protection, CodeQL,
  dependency review, private vulnerability reporting, or artifact
  attestations, which personal accounts cannot buy for private repos on any
  plan. Dependabot alerts and updates do work there. The gitleaks
  scan in `ci`, local hooks, and the process rules are the gate.
- GitHub Actions hardening:
  - every action pinned to a full commit SHA with a version comment;
  - top-level `permissions: {}`, write access granted per job only;
  - never `pull_request_target`;
  - never interpolate `github.event.*` into `run:`; pass it through `env:`;
  - concurrency groups with `cancel-in-progress` on PR workflows;
  - `timeout-minutes` on every job (the default is 6 hours);
  - GitHub App tokens request only the permissions the job needs
    (`permission-<name>` inputs);
  - the `zizmor` hook audits workflows, `dependabot.yml` and the pre-commit
    config for injection, permission and pinning mistakes (offline audits
    only, so the hook needs no token); `audit.sh` checks the timeouts
    (RS-CI-06) and the cooldown (RS-DEP-04).

## 10. Writing style

Commits and PRs follow Google's CL description guidance: a first line that
stands alone, then the problem, the approach, and its limits.

Docs follow the Google developer documentation style guide; section 15 has
the full documentation rules. Every README has: what it is, installation,
quick start, usage, development, contributing, license. Public repositories
show CI and release badges under the title, plus a license badge when they
have a license; private ones show the CI badge only, because the badge
services cannot read them.

Final design decisions get an ADR in `docs/dev/adr/` (context, decision,
consequences). Code follows the language style guide in section 11, enforced
by its linters and formatters, never by review comments alone.

## 11. Language overlays

| Overlay | Layout | Tools | Style guide | release-type |
|---|---|---|---|---|
| python | `src/<pkg>/`, `tests/`, `pyproject.toml` | uv, ruff (lint including the bandit security rules, format), mypy, pytest, coverage | Google Python style guide | python |
| ts | `src/`, `tests/` (pnpm workspace monorepos: planned for v2) | pnpm, eslint, prettier, tsc, vitest | Google TypeScript style guide | node |
| go | `cmd/<app>/`, `internal/`, `pkg/` only for public API | gofmt, go vet, golangci-lint, go test -race | Effective Go, Google Go style guide | go |
| r | package: `R/`, `tests/testthat/`, `DESCRIPTION` | lintr, styler, testthat (renv not yet in the overlay) | tidyverse style guide | r |
| swift | SwiftPM: `Sources/`, `Tests/`, `Package.swift` | swift-format, SwiftLint, swift test | Google Swift style guide | simple |
| docs | `docs/` (Diataxis) | Vale, markdownlint, lychee (all in base); Starlight for a site | Google developer docs style guide | simple |
| api-http (add-on) | `api/openapi.yaml` | Redocly CLI lint | OpenAPI 3.1 | n/a |
| api-events (add-on) | `api/asyncapi.yaml` | AsyncAPI CLI validate | AsyncAPI 3.0 | n/a |
| sensitive-data (add-on) | `tests/fixtures/synthetic/`, `docs/dev/data-handling.md` | gitleaks identifier rules (`.gitleaks.toml`), `no-data-files` hook, data `.gitignore` entries, Claude Code Read deny rules | 45 CFR 164.514 (Safe Harbor) for test data | n/a |
| citation (add-on) | `CITATION.cff`, `docs/how-to/cite.md` | none | Citation File Format 1.2.0 | n/a |
| base | none | EditorConfig, shellcheck, yamllint, actionlint, zizmor, gitleaks, Vale, markdownlint, lychee, check_docs | n/a | simple |

Jupyter notebooks use the python overlay with nbstripout. Static HTML sites
use the docs or ts overlay. Swift CI runs on macOS runners, which bill at a
10x rate on private repos; check the cost before using it there.

## 12. Per-repository adjustments

The standard is the same for every repository; what varies is the
individual repository. Repos link only to their own account's copy of
`repo-standard`. An account that must stay unlinked from the account
hosting the public source keeps its `repo-standard` and `repo-template`
copies private, publishes no `.github` defaults (a `.github` repo must be
public to apply), and its repos' CONTRIBUTING and AGENTS files state the
rules without a link. Its public repos still carry the same tooling files,
which code search can match. Before the first change in
a repo that has no recorded adjustments, Claude asks about and records in that
project's decisions file:

- visibility, license and any required file headers;
- sensitive data (for example PHI): such repos take the `sensitive-data`
  add-on (`--addon sensitive-data`), stay private, and keep real data out
  of git, GitHub and any AI tool not covered by an agreement for it;
- research software that people cite: take the `citation` add-on, which
  adds `CITATION.cff` for GitHub's citation button and explains Zenodo DOIs;
- CLA or contribution rules (for example a client or collaborator's);
- whether the repo publishes a docs site (section 15) and from which
  trigger;
- whether the user has admin rights. Without them, only files and hooks are
  applied, never repository settings.

## 13. Adopting the standard in an existing repo

1. Pilot one repo first, then the others one at a time, each confirmed.
2. Work on a `chore/adopt-repo-standard` branch and land it through a PR.
3. Run `scripts/apply-overlay.sh DIR OVERLAY --owner OWNER --retrofit
   [--public]`. It copies only missing files, skips sample source code, and
   parks fragments it cannot merge (for example the overlay's CI jobs) in
   `.scratch/repo-standard-merge/` for a hand merge. Nothing that exists is
   overwritten. It also:
   - adds missing `.gitignore` patterns under one
     `# Added by the repo standard` header;
   - adds every language found in tracked files to the CodeQL matrix (set
     the list yourself with `--codeql-langs "actions python ..."`);
   - warns about tracked symlinks, which CI cannot follow; commit the real
     file or remove the link before opening the PR;
   - turns on Dependabot alerts for the `origin` repo, because
     `dependency-review` fails on the adoption PR without the dependency
     graph (needs admin rights; otherwise turn them on by hand).
   Only files that are relevant or useful to the project stay. List the
   standard's files, folders, hooks and `.gitignore` lines a repo does not
   use in `.github/repo-standard-exclude`, one per line with the reason
   after `#`:

   ```text
   CODE_OF_CONDUCT.md        # no outside contributors
   .vale/                    # a trailing slash covers the whole folder
   hook:vale
   gitignore:site/
   RS-DEP-02                 # an audit rule, by its ID
   ```

   `apply-overlay.sh` never copies, parks or merges a listed item, so a
   re-run does not bring it back, and `audit.sh` reports it as N/A. A
   re-run also never appends an overlay section a file already has.
4. Never rewrite history. Set `bootstrap-sha` for release-please and the
   manifest version to the latest existing tag.
5. Existing coverage becomes the floor; it must not drop. Set
   `HOOKS_SCOPE: changed` in `ci.yml` so every hook (Vale, markdownlint,
   whitespace, ASCII and the rest) checks only the files a PR touches;
   older files are fixed as they are edited.
   Pin every existing workflow action to a full SHA in the same PR, because
   `apply-settings.sh` turns on required SHA pinning and skips it while any
   workflow on `main` is unpinned.
6. If the default branch is not `main`, rename it (asked per repo).
7. List any committed plan or notes files for the owner; never delete them
   automatically.
8. Run `scripts/apply-settings.sh` only after the PR merges and CI is green.

### Updating to a new release of the standard

A repository that follows the standard records the version in
`.github/repo-standard.yml`. To bring it up to a newer release:

```bash
scripts/update-repo.sh DIR [--to vX.Y.Z] [--dry-run]
```

The script renders the template and overlays at the recorded version and at
the target (default: the newest tag), each with that version's own scripts,
and merges the difference into each file with `git merge-file`. The
repository's own edits stay; only lines the standard changed move. It works
on a `chore/update-repo-standard-X.Y.Z` branch and leaves the changes
uncommitted for review. It:

- adds files that are new in the standard, and parks the standard's copy in
  `.scratch/repo-standard-update/` when the repository already has its own;
- removes files the standard dropped only when the repository never changed
  them;
- leaves `<<<<<<<` conflict markers where both sides changed the same lines
  (the `check-merge-conflict` hook blocks a commit until they are resolved);
- never touches files on the exclude list, sample source or tests.

Read the `CHANGELOG.md` entries between the two versions before merging: a
major release's `BREAKING CHANGE:` footer says what to do by hand. Repositories
adopted before the stamp existed need it first: write
`.github/repo-standard.yml` by hand with the version the files came from, or
pass `--from REF`. [ADR 0004](docs/dev/adr/0004-update-repositories-with-a-three-way-merge.md)
records why this is a script rather than Copier.

## 14. Labels

`type/bug`, `type/feature`, `type/docs`, `type/chore`, `priority/high`,
`priority/medium`, `priority/low`, `status/needs-triage`, `status/blocked`,
`good first issue`, `dependencies`, and the release-please labels
`autorelease: pending` and `autorelease: tagged`.

## 15. Documentation

Docs are code: they live in the repository, change only through pull
requests, and ship in the same PR as the behavior they describe.

### Structure (Diataxis)

`docs/` is organized by what the reader wants to do:

| Folder | Reader intent | Site sidebar label | `type` |
|---|---|---|---|
| `tutorials/` | Learn by doing a first task | Get started | `tutorial` |
| `how-to/` | Solve one specific problem | How to | `how-to` |
| `reference/` | Look up facts, options, API | Reference | `reference` |
| `explanation/` | Understand design and reasons | Concepts | `explanation` |
| `dev/` | Change the project (contributors) | never published | any |

- `docs/index.md` is the landing page (`type: overview`). Each section may
  have an `index.md` (`type: overview`).
- Folders are created with their first page, never empty in advance. Until
  a tutorial exists, the README quick start is the getting-started path.
- Architecture belongs in `explanation/architecture.md` once it is written,
  linking to the relevant ADRs.
- Every page starts with front matter. `title` and `type` follow the GitHub
  Docs model; `audience` is this standard's own field:

  ```yaml
  ---
  title: Install the CLI
  description: Install and verify the CLI on macOS, Linux or Windows.
  type: how-to          # tutorial | how-to | reference | explanation | overview
  audience: [user]      # one or more of: user, developer, admin
  ---
  ```

- The page H1 repeats the `title` (so the page reads correctly on GitHub).
  Repos whose site tool renders the title itself (Starlight) drop the H1
  and pass `--no-h1` to the `check-docs` hook.
- `scripts/check_docs.py` (a pre-commit hook) enforces the allowed folders,
  the front matter, `type` matching its folder, `developer` on every
  `docs/dev/` page, and exactly one H1 equal to `title` (headings inside
  code blocks are ignored).

### Style

- Base: Google developer documentation style guide. Where it is silent, the
  Microsoft Writing Style Guide.
- Second person, active voice, present tense.
- Headings are task-based and sentence case: `Install the CLI`, not
  `Installation`.
- Short sentences, numbered lists for steps, code in code blocks, Oxford
  comma.

### Checks (part of the required `ci` check)

The `hooks` job, which the `ci` aggregate requires, runs:

- **Vale** with the vendored Google package. Under `docs/dev/` (ADRs and
  contributor notes), first-person plural, future tense, and first person
  are warnings rather than errors. Errors fail the check; warnings
  are printed (the hook runs with `verbose: true`) but do not fail. Raised to error: `Google.Headings`,
  `Google.FirstPerson`, `Google.We`, `Google.Will`. `Google.Passive` stays a
  suggestion because it misfires on technical prose. Project terms go in
  `.vale/styles/config/vocabularies/Project/accept.txt`. Retrofitted repos
  set `HOOKS_SCOPE: changed` in `ci.yml` so only files a PR touches are
  checked.
- **markdownlint** on `.md` files.
- **lychee** in offline mode: internal links and anchors. External links run
  in the weekly `links.yml` workflow, which opens or updates one issue; a
  third-party outage never blocks a merge.
- **check_docs** as described above.

### Formats

- CommonMark `.md` by default.
- `.mdx` only in repos with a docs site that needs interactive components.
  markdownlint does not lint MDX reliably, so MDX is checked by Vale (mapped
  to Markdown) and Prettier.
- APIs ship a machine-readable spec in `api/`: OpenAPI 3.1 for HTTP
  (`api-http` add-on, linted with Redocly CLI), AsyncAPI 3.0 for events and
  messages (`api-events` add-on, validated with the AsyncAPI CLI). The spec
  is the source of truth.
- Reference pages are generated, never written by hand: from the API spec,
  and for code APIs from doc comments (TypeDoc, Sphinx autodoc2,
  pkg.go.dev, roxygen2 and pkgdown, DocC). Generated output lives in
  `docs/reference/api/`, which is gitignored and built when the site builds.

### Publishing (optional per repo)

- A repo that publishes docs builds a site and deploys it to GitHub Pages
  with the sidebar Get started, How to, Concepts, Reference. `docs/dev/` is
  never published.
- Trigger, recorded per repo: libraries and other versioned software deploy
  on `release: published` (plus a manual run). Apps that deploy from `main`,
  and docs-only repos, deploy on push to `main`, because `docs:` commits
  never cut a release.
- On the Free plan, GitHub Pages needs a public repo, so a published docs
  site is public.
- Site tool per overlay:

  | Overlay | Site tool | Why |
  |---|---|---|
  | ts, docs, go, swift | Starlight (Astro) | Cloudflare's developer docs run on it; built-in sidebar, search, and MDX. Go links to pkg.go.dev and Swift to its DocC output for the API reference. |
  | python | Sphinx with MyST Markdown and Furo | Generates the Python API reference natively (autodoc2). Material for MkDocs is in maintenance mode and reaches end of life on 2027-05-05; its successor, Zensical, entered a three-month beta with 0.1.0 on 2026-11-05. Neither is a choice for a new site yet. |
  | r | Starlight for guides, pkgdown for the function reference | pkgdown is the R standard for reference pages from roxygen2. |

  Starlight reads pages from `src/content/docs/`, and its docs loader has no
  option to change that. A custom content loader pointed at `docs/` mostly
  works, but last-updated dates and generated sidebars are known gaps. This
  is an open decision for the first site: a custom loader, or a build step
  that copies `docs/` into `src/content/docs/`.
  Site scaffolding, the Pages deploy workflow, and reference generation are
  built when the first repo opts in, not before. Until then an API repo has
  a linted spec but no generated reference pages.

### What is never committed

- Plans, research, AI session notes, drafts, and other temporary working
  files go in `.scratch/` (gitignored). `.remember/` and
  `.claude/settings.local.json` are also local only.
- The `no-scratch-files` hook rejects any `.md`, `.mdx`, or `.txt` file whose
  name contains plan, notes, research, session, draft, scratch, todo,
  brainstorm, handoff, or worklog as a word (so `IMPLEMENTATION_PLAN.md`,
  `design-notes.md`, and `HANDOFF.md` are caught, `explanation.md` is not).
  Published docs pages, ADRs, and `release-notes` files are exempt;
  `docs/dev/` is checked, because that is where notes tend to drift in. The
  `no-local-only-folders` hook rejects anything under `.scratch/` or
  `.remember/`, even when force-added.
- Only final decisions are committed, as ADRs in `docs/dev/adr/`.
- When retrofitting, existing plan or notes files are listed for the owner,
  never deleted automatically.

## Sources

Conventional Commits 1.0; Angular commit message guidelines; Kubernetes
contributor guide; Go contribution guide; Google eng-practices (CL
descriptions, small CLs, review standard); GitHub docs (GitHub flow,
rulesets, merge methods, security features, Actions hardening); Driessen's
2020 note on git-flow; Atlassian Gitflow page; DORA trunk-based development;
Microsoft branching guidance and Release Flow; OpenSSF Scorecard and Concise
Guide; release-please and release-please-action READMEs; Dependabot options
reference; Diataxis; Google developer documentation style guide;
Microsoft Writing Style Guide; Vale and the errata-ai Google package;
lychee; Redocly CLI; AsyncAPI CLI; Cloudflare's post on moving its docs to
Starlight; Material for MkDocs maintenance notice.
