#!/usr/bin/env bash
# Usage: sync.sh OWNER TARGET [--create]
#   TARGET is one of:
#     template  OWNER/repo-template: reference copy of template/ (placeholders
#               kept); a repo created from it in the GitHub UI is finished
#               with scripts/finish-repo.sh
#     defaults  OWNER/.github: default community health files for repos that
#               have none (publish only after the pilot retrofit). Source
#               owner only: a .github repo must be public to apply.
#     standard  OWNER/repo-standard: a copy of STANDARD.md for an account that
#               is not the source owner
# Accounts other than the source owner keep their repo-template and
# repo-standard copies private, so code search cannot match them to the
# source account.
# Updates go through a pull request on a unique chore/sync-repo-standard-*
# branch, never a push to main. --create makes a missing repo with one
# bootstrap commit and applies the standard settings.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

owner="${1:?owner}"; target="${2:?template|defaults|standard}"; create=0
[ "${3:-}" = --create ] && create=1
load_owner "$owner"
if [ -n "$(git -C "$STANDARD_ROOT" status --porcelain)" ]; then
  die "repo-standard has uncommitted changes; commit them first so the source SHA is exact"
fi
src_sha="$(git -C "$STANDARD_ROOT" rev-parse --short HEAD)"
# A source SHA is searchable and would lead from this account to the source
# repo, so only the source owner's repos record it.
if is_source_owner "$owner"; then src_note="Source: repo-standard@$src_sha"; else src_note="Synced from the maintained standard."; fi
branch="chore/sync-repo-standard-$(date +%Y%m%d-%H%M%S)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

render_owner() { # DIR: fill __OWNER__ / __OWNER_ID__ only
  local id; id="$(gh_as "$owner" api user --jq .id)"
  grep -rlI -e __OWNER__ -e __OWNER_ID__ "$1" 2>/dev/null | while read -r f; do
    OWNER="$owner" OID="$id" perl -pi -e 's/__OWNER_ID__/$ENV{OID}/g; s/__OWNER__/$ENV{OWNER}/g' "$f"
  done
}
stage_base() { # DIR: CI and hook configuration so the repo passes its own checks
  local t="$STANDARD_ROOT/template"
  mkdir -p "$1/.github/workflows" "$1/scripts"
  cp "$t/.github/workflows/ci.yml" "$t/.github/workflows/pr-title.yml" "$t/.github/workflows/links.yml" "$1/.github/workflows/"
  cp "$t/.github/dependabot.yml" "$t/.github/CODEOWNERS" "$1/.github/"
  for f in .pre-commit-config.yaml .markdownlint.yaml .editorconfig .gitattributes .gitignore .vale.ini .lychee.toml; do cp "$t/$f" "$1/$f"; done
  copy_tree "$t/.vale" "$1/.vale"
  cp "$t/scripts/check_docs.py" "$1/scripts/"
}
stage_template() {
  copy_tree "$STANDARD_ROOT/template" "$1"
  # Fill what would fail this repo's own hooks; keep the rest for finish-repo.sh.
  perl -pi -e 's/__DESCRIPTION__/One-paragraph description of this project./g' "$1/README.md"
  perl -pi -e 's/__REPO_NAME__/this project/g' "$1/docs/index.md" "$1/docs/dev/index.md"
  # The template repo itself needs a license; finish-repo.sh replaces it.
  cp "$STANDARD_ROOT/LICENSE" "$1/LICENSE"
  render_owner "$1"
  is_source_owner "$owner" || delink_standard "$1"
}
stage_defaults() {
  stage_base "$1"
  copy_tree "$STANDARD_ROOT/org-defaults" "$1"
  cp "$STANDARD_ROOT/template/CODE_OF_CONDUCT.md" "$1/"
  copy_tree "$STANDARD_ROOT/template/.github/ISSUE_TEMPLATE" "$1/.github/ISSUE_TEMPLATE" --delete
  # Default community files have no repository of their own: questions go to
  # the SUPPORT.md in OWNER/.github.
  perl -pi -e 's#/__REPO_NAME__/blob/main/SUPPORT\.md#/.github/blob/main/SUPPORT.md#' "$1/.github/ISSUE_TEMPLATE/config.yml"
  render_owner "$1"
}
stage_standard() {
  stage_base "$1"
  cp "$STANDARD_ROOT/STANDARD.md" "$STANDARD_ROOT/LICENSE" "$1/"
  cp "$STANDARD_ROOT/template/CODE_OF_CONDUCT.md" "$STANDARD_ROOT/template/SECURITY.md" "$1/"
  cat > "$1/README.md" <<'README'
# repo-standard

The repository standard every repository of this account follows. Read
[STANDARD.md](STANDARD.md).

Changes arrive as pull requests from the sync script.

## License

See [LICENSE](LICENSE).
README
  render_owner "$1"
}

sync_repo() {
  local repo="$1" stager="$2" desc="$3" dir="$work/$1"
  if ! gh_as "$owner" repo view "$owner/$repo" >/dev/null 2>&1; then
    [ "$create" = 1 ] || die "$owner/$repo does not exist; re-run with --create"
    info "creating $owner/$repo"
    mkdir -p "$dir"; git -C "$dir" init -q -b main; set_identity "$dir" "$owner"
    "$stager" "$dir"
    git -C "$dir" add -A
    git -C "$dir" commit -q -m "chore: bootstrap from repo-standard" -m "$src_note"
    gh_as "$owner" repo create "$owner/$repo" "--$vis" --description "$desc" --source "$dir" --remote origin --push
    [ "$repo" = repo-template ] && gh_as "$owner" api -X PATCH "repos/$owner/$repo" -F is_template=true --silent
    "$STANDARD_ROOT/scripts/apply-settings.sh" "$owner/$repo" "$vis"
    return
  fi
  info "syncing $owner/$repo"
  gh_as "$owner" repo clone "$owner/$repo" "$dir" -- -q
  set_identity "$dir" "$owner"
  git -C "$dir" switch -q -c "$branch"
  find "$dir" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
  "$stager" "$dir"
  git -C "$dir" add -A
  if git -C "$dir" diff --cached --quiet; then info "$owner/$repo already up to date"; return; fi
  git -C "$dir" commit -q -m "chore: sync with repo-standard" -m "$src_note"
  git -C "$dir" push -q -u origin "$branch"
  gh_as "$owner" pr create --repo "$owner/$repo" --head "$branch" --title "chore: sync with repo-standard" \
    --body "Generated by scripts/sync.sh. $src_note Review the diff, then squash-merge."
}

vis=public; is_source_owner "$owner" || vis=private
case "$target" in
  template) sync_repo repo-template stage_template "Template for new repositories (reference copy; finish with finish-repo.sh)" ;;
  defaults)
    is_source_owner "$owner" ||
      die "$owner stays unlinked: its .github would have to be public to apply, so it gets none"
    sync_repo .github stage_defaults "Default community health files" ;;
  standard)
    ! is_source_owner "$owner" ||
      die "$owner hosts the source repo-standard; change it through a PR there instead"
    sync_repo repo-standard stage_standard "The repository standard for this account (published copy)" ;;
  *) die "unknown target '$target' (template, defaults or standard)" ;;
esac
