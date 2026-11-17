---
title: Sources to recheck
description: The outside sources the standard depends on, how often to recheck each one, and what a change in it can mean for the standard.
type: reference
audience: [developer]
---

# Sources to recheck

The standard repeats facts from outside sources: what GitHub offers on each
plan, what the OpenSSF Baseline requires, how tools behave. When a source
changes, the standard can become wrong without anyone noticing. On the first
day of each month, the `standard-review` workflow opens one issue listing
the groups below that are due that month. Work through the issue, open one
issue for each change the standard needs, and close the review issue with a
short summary.

Tool versions are not on this list: Dependabot proposes them, and
`scripts/sync-pins.sh` copies them into `template/` and `overlays/`.

## Monthly

| Source | What it can change |
|---|---|
| [GitHub changelog](https://github.blog/changelog/) | Rulesets, Actions, security features and their plans (sections 7 and 9) |
| [OpenSSF blog](https://openssf.org/blog/) | New guidance and tools for section 9 |

## Quarterly

Due in January, April, July and October.

| Source | What it can change |
|---|---|
| [OSPS Baseline releases](https://github.com/ossf/security-baseline/releases) | The control IDs in [audit rules](../reference/audit-rules.md) |
| [Scorecard checks](https://github.com/ossf/scorecard/blob/main/docs/checks.md) | The public overlay and the workflow rules |
| [GitHub Actions secure use](https://docs.github.com/en/actions/reference/security/secure-use) | Workflow hardening in section 9 and `RS-CI-*` rules |
| [release-please releases](https://github.com/googleapis/release-please/releases) | Release rules in section 8 |
| [Scientific Python cookie](https://github.com/scientific-python/cookie) | The python overlay |
| [PyPI trusted publishers](https://docs.pypi.org/trusted-publishers/) and [npm trusted publishers](https://docs.npmjs.com/trusted-publishers) | Publishing from CI |
| [Claude Code docs](https://code.claude.com/docs/en/overview) and [AGENTS.md](https://agents.md/) | `AGENTS.md`, `.claude/settings.json` and the agent rules |

## Twice a year

Due in January and July.

| Source | What it can change |
|---|---|
| [GitHub customer terms](https://github.com/customer-terms) and [Anthropic commercial terms](https://www.anthropic.com/legal/commercial-terms) | Where sensitive data may go (the `sensitive-data` add-on) |
| AI contribution policies of [LLVM](https://llvm.org/docs/AIToolPolicy.html), the [Linux kernel](https://docs.kernel.org/process/coding-assistants.html) and [Fedora](https://docs.fedoraproject.org/en-US/council/policy/ai-contribution-policy/) | The AI disclosure and attribution rules in section 5 |
| [r-lib/actions](https://github.com/r-lib/actions), [renv](https://github.com/rstudio/renv), [Air](https://github.com/posit-dev/air) and [Quarto](https://github.com/quarto-dev/quarto-cli/releases) | The r overlay |
| [Starlight](https://github.com/withastro/starlight/releases) and [Zensical](https://zensical.org/) | The docs site choice in section 15 |

## Yearly

Due in January.

| Source | What it can change |
|---|---|
| Well-run repositories in each overlay's language | Files and settings the standard does not have yet |
| [Citation File Format](https://citation-file-format.github.io/) and [Zenodo](https://zenodo.org/) | The `citation` add-on |
