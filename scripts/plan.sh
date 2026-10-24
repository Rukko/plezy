#!/usr/bin/env bash
# Decide whether a custom build is needed and which version it gets.
#
# Env: UPSTREAM, FORK (owner/name), INPUT_TAG (optional upstream tag),
#      FORCE ("true" rebuilds an already released combination), GITHUB_OUTPUT.
set -euo pipefail
: "${UPSTREAM:?}" "${FORK:?}" "${GITHUB_OUTPUT:?}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tag="${INPUT_TAG:-}"
if [[ -z "$tag" ]]; then
  tag=$(gh api "repos/$UPSTREAM/releases/latest" --jq .tag_name)
fi

pubspec_version=$(gh api "repos/$UPSTREAM/contents/pubspec.yaml?ref=$tag" --jq .content | base64 -d |
  sed -n -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+).*$/\1/p')
if [[ -z "$pubspec_version" ]]; then
  echo "::error::Could not read the pubspec version of $UPSTREAM at $tag"
  exit 1
fi
version=${pubspec_version%%+*}
upstream_build=${pubspec_version#*+}

branches=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line=${line%%#*}
  line=$(echo "$line" | xargs)
  [[ -n "$line" ]] && branches+=("$line")
done < "$root/patches.txt"

heads=""
for branch in "${branches[@]}"; do
  sha=$(git ls-remote "https://github.com/$FORK.git" "refs/heads/$branch" | cut -f1)
  if [[ -z "$sha" ]]; then
    echo "::error::Patch branch $branch does not exist in $FORK"
    exit 1
  fi
  heads+="$branch@$sha"$'\n'
done
fingerprint=$(printf '%s\n%s' "$tag" "$heads" | sha256sum | cut -c1-16)

# Revisions of this upstream version already released by the fork, and whether
# one of them was built from exactly these patch heads.
rev=0
existing=""
while IFS= read -r release_tag; do
  [[ "$release_tag" =~ ^${version//./\\.}-r([0-9]+)$ ]] || continue
  n=${BASH_REMATCH[1]}
  (( n + 1 > rev )) && rev=$((n + 1))
  if gh release view "$release_tag" -R "$FORK" --json body --jq .body | grep -qF "fingerprint: $fingerprint"; then
    existing=$release_tag
  fi
done < <(gh release list -R "$FORK" --limit 200 --json tagName --jq '.[].tagName')

build=true
if [[ -n "$existing" && "${FORCE:-false}" != "true" ]]; then
  build=false
fi

# WinSparkle compares the 16-bit build number of the executable, so each fork
# revision gets its own slot above the upstream build it is based on.
if (( rev > 9 )); then
  echo "::error::$version already has 10 fork revisions; the build number scheme has no room left"
  exit 1
fi
build_number=$((upstream_build * 10 + rev))
if (( build_number > 65535 )); then
  echo "::error::Build number $build_number does not fit WinSparkle's 16-bit field"
  exit 1
fi

{
  echo "build=$build"
  echo "tag=$tag"
  echo "version=$version"
  echo "build_number=$build_number"
  echo "release_tag=$version-r$rev"
  echo "fingerprint=$fingerprint"
  echo "branches=${branches[*]}"
  echo "heads<<EOF"
  printf '%s' "$heads"
  echo "EOF"
} >> "$GITHUB_OUTPUT"

echo "Upstream $tag ($pubspec_version), fingerprint $fingerprint"
printf '%s' "$heads"
if [[ "$build" == "true" ]]; then
  echo "Building $version-r$rev with build number $build_number"
else
  echo "Already released as $existing, nothing to do"
fi
