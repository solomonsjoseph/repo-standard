#!/usr/bin/env bash
# Usage: check-drift.sh   (run from anywhere; used as a repo-standard hook)
# repo-standard follows its own standard, so several root files are copies of
# template/ files. This fails when a copy drifts, and when the plan-file name
# rule in scripts/lib.sh no longer matches the no-scratch-files hook, and when
# an action or hook is pinned to different commits in different files.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
cd "$STANDARD_ROOT" || exit 1
status=0
# Identical copies. Files that differ on purpose are not listed: README.md,
# CONTRIBUTING.md and AGENTS.md (owner filled in), .github/CODEOWNERS,
# .pre-commit-config.yaml (extra excludes for template/ and overlays/),
# release-please-config.json and the manifest.
for f in .editorconfig .gitattributes .gitignore .git-blame-ignore-revs .markdownlint.yaml .vale.ini .lychee.toml \
  CODE_OF_CONDUCT.md SECURITY.md SUPPORT.md .claude/settings.json scripts/check_docs.py \
  .github/pull_request_template.md .github/dependabot.yml \
  .github/ISSUE_TEMPLATE/bug_report.yml .github/ISSUE_TEMPLATE/feature_request.yml \
  .github/workflows/ci.yml .github/workflows/pr-title.yml .github/workflows/release-please.yml .github/workflows/links.yml \
  .github/workflows/main-guard.yml; do
  if ! cmp -s "$f" "template/$f"; then echo "drift: $f differs from template/$f"; status=1; fi
done
# Copies with the template's __OWNER__ and __REPO_NAME__ filled in.
# The slug comes from the root file itself, so forks and synced copies pass.
slug="$(sed -nE 's#.*https://github\.com/([^/]+/[^/]+)/blob/main/SUPPORT\.md.*#\1#p' .github/ISSUE_TEMPLATE/config.yml | head -n 1)"
# shellcheck disable=SC2043  # a list of one, for now
for f in .github/ISSUE_TEMPLATE/config.yml; do
  if ! sed -e "s#__OWNER__#${slug%%/*}#g" -e "s#__REPO_NAME__#${slug#*/}#g" "template/$f" | cmp -s - "$f"; then
    echo "drift: $f differs from template/$f (placeholders filled in)"; status=1
  fi
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
# The Unicode rules (ascii-only exclude, no-invisible-unicode pattern) are the
# same in the root and template configs.
for spec in ascii-only:exclude no-invisible-unicode:entry; do
  hook="${spec%%:*}"; key="${spec#*:}"
  get() { grep -A6 "id: $hook\$" "$1" | grep -m1 "^ *$key: "; }
  if [ -z "$(get template/.pre-commit-config.yaml)" ] || [ "$(get .pre-commit-config.yaml)" != "$(get template/.pre-commit-config.yaml)" ]; then
    echo "drift: the $hook $key differs between the root and template pre-commit configs"; status=1
  fi
done
# Each language overlay's _ci.yml is the template's ci.yml plus a "test" job:
# the shared jobs (hooks, secrets, the ci aggregate) must match the template.
# Ignored: the header comment, blank lines, the SKIP list and the needs list,
# which the "ci" job must keep complete (every other job in it).
ci_shared() {
  perl -ne 'next if $. <= 2 && /^#/; if (/^  test:$/) { $t = 1; next } $t = 0 if $t && /^  \S/;
    next if $t || /^\s*$/; s/^(\s*SKIP:).*/$1/; s/^(\s*needs:).*/$1/; print' "$1"
}
ci_needs_ok() {
  perl -ne '$in = 1 if /^jobs:/; push @jobs, $1 if $in && /^  ([\w-]+):\s*$/ && $1 ne "ci";
    $needs = $1 if /^\s+needs: \[(.*)\]/;
    END { my %n = map { $_ => 1 } split /,\s*/, $needs; exit((grep { !$n{$_} } @jobs) ? 1 : 0) }' "$1"
}
for f in template/.github/workflows/ci.yml overlays/*/_ci.yml; do
  if [ "$f" != template/.github/workflows/ci.yml ] && ! ci_shared "$f" | cmp -s - <(ci_shared template/.github/workflows/ci.yml); then
    echo "drift: the hooks, secrets or ci job in $f differs from template/.github/workflows/ci.yml"; status=1
  fi
  ci_needs_ok "$f" || { echo "drift: the ci job in $f does not need every other job"; status=1; }
done
# Action SHAs and hook revisions must agree across root, template/ and overlays/.
"$STANDARD_ROOT/scripts/sync-pins.sh" --check || status=1
exit "$status"
