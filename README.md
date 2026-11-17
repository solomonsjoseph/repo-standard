# repo-standard

The GitHub repository standard for every repository of this account, plus
the templates and scripts that apply it. Read
[STANDARD.md](STANDARD.md) for the rules.

## Quick start

Create a new repository that follows the standard:

```bash
scripts/new-repo.sh OWNER my-tool python public --license apache-2.0 --desc "One line about it"
```

Check an existing repository (read-only):

```bash
scripts/audit.sh OWNER/my-tool ~/path/to/my-tool
```

## Usage

| Script | What it does |
|---|---|
| `scripts/new-repo.sh` | Builds a repo from `template/` plus an overlay and add-ons, makes the bootstrap commit, creates it on GitHub, applies settings |
| `scripts/finish-repo.sh` | Finishes a repo created from `repo-template` in the GitHub UI, through a PR |
| `scripts/apply-overlay.sh` | Adds a language overlay or add-on; `--retrofit` copies only missing files into an existing repo |
| `scripts/apply-settings.sh` | Merge options, Actions permissions, security features, labels, the `main` and `release-tags` rulesets (idempotent) |
| `scripts/audit.sh` | Reports pass, fail, or not applicable for every rule (read-only) |
| `scripts/sync.sh` | Publishes `repo-template`, `.github` defaults, or a `repo-standard` copy to an account through PRs |
| `scripts/enable-private-reporting.sh` | Turns on private vulnerability reporting for an account's public repos |
| `scripts/check-drift.sh` | Checks that this repo's copies of template files have not drifted (a hook) |
| `scripts/setup-machine.sh` | One-time machine setup: the pre-push guard as a git template hook and the identity hook for Claude Code |
| `scripts/doctor.sh` | Checks that this machine can run the scripts: tools, versions, private config, gh logins, Windows settings (read-only) |
| `scripts/test-lib.sh` | Tests the portable helpers in `scripts/lib.sh` (a hook) |

The scripts run in bash on macOS, Linux, and Windows (Git Bash). On a new
machine, run `scripts/setup-machine.sh` once; it ends by running
`scripts/doctor.sh`.

Private per-owner settings live in `~/.config/repo-standard/OWNER.env`; see
`scripts/lib.sh`.

## Development

- `template/` is the base skeleton every repo gets.
- `overlays/<lang>/` adds a language layout; files starting with `_` are merge
  fragments (see `scripts/apply-overlay.sh`).
- `overlays/public/` adds CodeQL, dependency review, and Scorecard.
- `org-defaults/` holds the extra files for each account's `.github` repo.
- Decisions are recorded as ADRs in `docs/dev/adr/`.

Change the standard through a PR. Merging the release PR tags a new
`vX.Y.Z` and updates `CHANGELOG.md` (see
[ADR 0002](docs/dev/adr/0002-version-the-standard.md) for what counts as
major, minor, or patch). After each release, run `scripts/sync.sh` for each
account.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

See [LICENSE](LICENSE).
