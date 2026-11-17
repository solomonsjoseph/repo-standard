#!/usr/bin/env bash
# Usage: check-drift.sh   (run from anywhere; used as a repo-standard hook)
# repo-standard follows its own standard, so several root files are copies of
# template/ files. This fails when a copy drifts, and when the plan-file name
# rule in scripts/lib.sh no longer matches the no-scratch-files hook.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
cd "$STANDARD_ROOT" || exit 1
status=0
# Identical copies. Files that differ on purpose are not listed: README.md,
# CONTRIBUTING.md and AGENTS.md (owner filled in), .github/CODEOWNERS,
# .pre-commit-config.yaml (extra excludes for template/ and overlays/),
# release-please-config.json and the manifest.
for f in .editorconfig .gitattributes .gitignore .markdownlint.yaml .vale.ini .lychee.toml \
  CODE_OF_CONDUCT.md SECURITY.md SUPPORT.md .claude/settings.json scripts/check_docs.py \
  .github/pull_request_template.md .github/dependabot.yml \
  .github/ISSUE_TEMPLATE/bug_report.yml .github/ISSUE_TEMPLATE/feature_request.yml .github/ISSUE_TEMPLATE/config.yml \
  .github/workflows/ci.yml .github/workflows/pr-title.yml .github/workflows/release-please.yml .github/workflows/links.yml \
  .github/workflows/main-guard.yml; do
  if ! cmp -s "$f" "template/$f"; then echo "drift: $f differs from template/$f"; status=1; fi
done
if ! diff -rq .vale template/.vale >/dev/null; then echo "drift: .vale/ differs from template/.vale/"; status=1; fi
hook_re="$(grep -A14 'id: no-scratch-files' template/.pre-commit-config.yaml | sed -n 's/^ *files: (?i)//p')"
[ "$hook_re" = "$SCRATCH_NAME_RE" ] || { echo "drift: SCRATCH_NAME_RE in scripts/lib.sh differs from the no-scratch-files hook"; status=1; }
hook_ex="$(grep -A14 'id: no-scratch-files' template/.pre-commit-config.yaml | sed -n 's/^ *exclude: (?i)//p')"
[ "$hook_ex" = "$SCRATCH_EXEMPT_RE" ] || { echo "drift: SCRATCH_EXEMPT_RE in scripts/lib.sh differs from the no-scratch-files hook"; status=1; }
# The AI attribution pattern lives in both pre-commit configs (commit-msg
# hook) and in pr-title.yml (PR body check); all three must agree.
ai_re() { grep -A8 'id: no-ai-attribution' "$1" | sed -n "s/^ *entry: '(?i)\(.*\)'\$/\1/p"; }
ai_root="$(ai_re .pre-commit-config.yaml)"
ai_body="$(sed -n "s/^ *pattern='\(.*\)'\$/\1/p" template/.github/workflows/pr-title.yml)"
if [ -z "$ai_root" ] || [ "$ai_root" != "$(ai_re template/.pre-commit-config.yaml)" ] || [ "$ai_root" != "$ai_body" ]; then
  echo "drift: the AI attribution pattern differs between the pre-commit configs and pr-title.yml"; status=1
fi
exit "$status"
