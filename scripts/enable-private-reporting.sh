#!/usr/bin/env bash
# Usage: enable-private-reporting.sh OWNER
# Turns on private vulnerability reporting for every public, non-archived,
# non-fork repository of OWNER. Run it when OWNER/.github goes live, because
# the default SECURITY.md points reporters at that button. Safe to re-run.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

owner="${1:?owner}"
load_owner "$owner"
gh_as "$owner" repo list "$owner" --visibility public --no-archived --source --limit 500 \
  --json name --jq '.[].name' | while read -r repo; do
  if gh_as "$owner" api -X PUT "repos/$owner/$repo/private-vulnerability-reporting" --silent; then
    echo "enabled  $owner/$repo"
  else
    echo "FAILED   $owner/$repo" >&2
  fi
done
