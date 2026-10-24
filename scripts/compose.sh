#!/usr/bin/env bash
# Stack the fork's patch branches on an upstream release and export the result
# as a patch series that applies cleanly, with `git am`, to that release.
#
# Usage: compose.sh TAG OUT_DIR BRANCH...
# Env:   UPSTREAM, FORK (owner/name).
#
# Generated translation files (lib/i18n/strings*.g.dart) change in almost every
# upstream release. A conflict confined to them keeps the upstream copy, and the
# build regenerates them with slang, so they never block a release.
set -euo pipefail
: "${UPSTREAM:?}" "${FORK:?}"
tag=$1
out=$2
shift 2

mkdir -p "$out"
out=$(cd "$out" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

git() { command git -C "$work" "$@"; }

git init -q
git config user.name "plezy-custom-build"
git config user.email "plezy-custom-build@users.noreply.github.com"
git remote add upstream "https://github.com/$UPSTREAM.git"
git remote add fork "https://github.com/$FORK.git"
git fetch -q --filter=blob:none upstream \
  "refs/heads/main:refs/remotes/upstream/main" "refs/tags/$tag:refs/tags/$tag"
for branch in "$@"; do
  git fetch -q --filter=blob:none fork "refs/heads/$branch:refs/remotes/fork/$branch"
done
git checkout -q --detach "refs/tags/$tag"

for branch in "$@"; do
  base=$(git merge-base upstream/main "fork/$branch")
  for commit in $(git rev-list --reverse "$base..fork/$branch"); do
    subject=$(git log -1 --format=%s "$commit")
    if git cherry-pick --empty=drop "$commit" > /dev/null 2>&1; then
      echo "Applied $branch: $subject"
      continue
    fi
    conflicts=$(git diff --name-only --diff-filter=U)
    if [[ -n "$conflicts" ]] && ! grep -qvE '^lib/i18n/strings[^/]*\.g\.dart$' <<< "$conflicts"; then
      git checkout --ours -- $conflicts
      git add -- $conflicts
      if git diff --cached --quiet; then
        git cherry-pick --skip
      else
        GIT_EDITOR=true git cherry-pick --continue > /dev/null
      fi
      echo "Applied $branch: $subject (kept upstream generated translations)"
      continue
    fi
    echo "::error::$branch no longer applies to $UPSTREAM $tag at \"$subject\""
    git status --short
    exit 1
  done
done

git format-patch -q -o "$out" "refs/tags/$tag..HEAD"
echo "Exported $(ls "$out" | wc -l) patch(es) to $out"
