# Repo standard

Version 1.2 (2026-11-12). This is the standard every repository of the
account follows. It combines practices from Google (Angular, Kubernetes, Go,
eng-practices), Microsoft (VS Code, TypeScript, Release Flow), Meta (React),
AWS (CDK), GitHub's own guidance, DORA research, and the OpenSSF security
baselines, sized for a solo maintainer.

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
   (`api-http`, `api-events`), whether the repo publishes a docs site, and
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
   never reads the key. Keep the key in the macOS Keychain rather than as a
   file. The Keychain returns multi-line values as hex, so store the key
   base64-encoded, once per account, then delete the downloaded file:

   ```bash
   security add-generic-password -s release-app-key -a OWNER -w "$(base64 < release-app.pem)"
   ```

   Then, for each repo:

   ```bash
   security find-generic-password -s release-app-key -a OWNER -w | base64 -d | gh secret set RELEASE_APP_PRIVATE_KEY --repo OWNER/NAME
   ```

   Until the key, the `RELEASE_APP_CLIENT_ID` variable, and the App
   installation all exist, the release workflow reports "not configured"
   and succeeds.

4. Clone and install hooks (install pre-commit with `uv tool install pre-commit`;
   versions before 4.7 fail with current npm):

   ```bash
   pre-commit install --hook-type pre-commit --hook-type commit-msg
   ```

The bootstrap commit is the only commit that goes straight to `main`.

The scripts read private per-owner settings from
`~/.config/repo-standard/OWNER.env` (display name, release App client id,
SSH signing key) and refuse owners without one.

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
README.md                 what it is, quick start, usage, development, contributing, license
LICENSE                   chosen per repo
CHANGELOG.md              written by release-please, never by hand
CONTRIBUTING.md           how to propose and land a change (this standard, short form)
SECURITY.md               how to report a vulnerability privately
CODE_OF_CONDUCT.md        adopts Contributor Covenant 2.1
AGENTS.md                 instructions for coding agents; CLAUDE.md points here
.editorconfig  .gitattributes  .gitignore
.pre-commit-config.yaml   local hooks, also run in CI
release-please-config.json  .release-please-manifest.json
.github/
  ISSUE_TEMPLATE/         bug_report.yml, feature_request.yml, config.yml
  pull_request_template.md
  CODEOWNERS              routing only, never a required review
  dependabot.yml
  workflows/              ci.yml, pr-title.yml, release-please.yml
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
- Source files are English and plain ASCII only. Build any non-ASCII test
  value from escapes.

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
- One logical change per commit. Commits are signed with SSH when the
  owner's private config sets `SIGNING_KEY` (the key must also be added on
  GitHub as a signing key); the ruleset does not require signatures yet.
- No AI attribution lines in commits or PRs.

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
| No open high or critical security alerts | process rule (CodeQL, Dependabot, secret scanning) |

`ci` is one aggregate job that depends on every other CI job, always runs,
and fails unless each dependency succeeded. Only `ci` and `pr-title` are
required, so a job that is skipped or never reports cannot block or silently
pass a merge.

Required approvals and required CODEOWNERS review are off: a solo maintainer
cannot approve their own PR. They are switched on the day a second
maintainer joins.

On private repos under the Free plan the ruleset may not be enforceable.
There the same gate holds through CI, local hooks and the process rules, and
Claude never pushes directly to `main`.

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
- Repos that publish packages or binaries add artifact attestations (or
  signed releases) and an SBOM.

## 9. Security and supply chain

- MFA on every account.
- `SECURITY.md` and private vulnerability reporting on every repo.
- Dependabot alerts and security updates on. Version updates for every
  ecosystem in the repo, including `github-actions`, with a 5-day cooldown
  for non-security updates. Commit prefixes: `fix(deps)` for production
  dependencies, `chore(deps-dev)` for development dependencies.
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
- Private repos on the Free plan have no rulesets and no GitHub secret
  scanning (rulesets are public-only on Free). There the gitleaks scan in
  `ci`, local hooks, and the process rules are the gate.
- GitHub Actions hardening:
  - every action pinned to a full commit SHA with a version comment;
  - top-level `permissions: {}`, write access granted per job only;
  - never `pull_request_target`;
  - never interpolate `github.event.*` into `run:`; pass it through `env:`;
  - concurrency groups with `cancel-in-progress` on PR workflows.
- Coverage: in the python and ts overlays new repos fail under 80 percent;
  go, r, and swift report coverage only. Retrofitted repos set their current
  coverage as the floor.

## 10. Writing style

Commits and PRs follow Google's CL description guidance: a first line that
stands alone, then the problem, the approach, and its limits.

Docs follow the Google developer documentation style guide; section 15 has
the full documentation rules. Every README has: what it is, quick start,
usage, development, contributing, license.

Final design decisions get an ADR in `docs/dev/adr/` (context, decision,
consequences). Code follows the language style guide in section 11, enforced
by its linters and formatters, never by review comments alone.

## 11. Language overlays

| Overlay | Layout | Tools | Style guide | release-type |
|---|---|---|---|---|
| python | `src/<pkg>/`, `tests/`, `pyproject.toml` | uv, ruff (lint, format), mypy, pytest, coverage | Google Python style guide | python |
| ts | `src/`, `tests/` (pnpm workspace monorepos: planned for v2) | pnpm, eslint, prettier, tsc, vitest | Google TypeScript style guide | node |
| go | `cmd/<app>/`, `internal/`, `pkg/` only for public API | gofmt, go vet, golangci-lint, go test -race | Effective Go, Google Go style guide | go |
| r | package: `R/`, `tests/testthat/`, `DESCRIPTION` | lintr, styler, testthat, renv | tidyverse style guide | r |
| swift | SwiftPM: `Sources/`, `Tests/`, `Package.swift` | swift-format, SwiftLint, swift test | Google Swift style guide | simple |
| docs | `docs/` (Diataxis) | Vale, markdownlint, lychee (all in base); Starlight for a site | Google developer docs style guide | simple |
| api-http (add-on) | `api/openapi.yaml` | Redocly CLI lint | OpenAPI 3.1 | n/a |
| api-events (add-on) | `api/asyncapi.yaml` | AsyncAPI CLI validate | AsyncAPI 3.0 | n/a |
| base | none | EditorConfig, shellcheck, yamllint, actionlint, gitleaks, Vale, markdownlint, lychee, check_docs | n/a | simple |

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
- sensitive data rules (for example PHI): no real data in fixtures,
  stricter secret scanning, data-handling notes in `SECURITY.md`;
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
  | python | Sphinx with MyST Markdown and Furo | Generates the Python API reference natively (autodoc2). Material for MkDocs reported the end of its maintenance period in November 2026 and its successor, Zensical, is still early; check both before choosing them. |
  | r | Starlight for guides, pkgdown for the function reference | pkgdown is the R standard for reference pages from roxygen2. |

  Starlight reads pages from `src/content/docs/` by default; mapping it to
  `docs/` is decided when the first site is scaffolded (unverified).
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
