#!/usr/bin/env bash
#
# Determine which dev builds are needed and emit a build matrix.
#
# Builds are planned for:
#   - a single PR or branch, when requested via workflow inputs
#     (INPUT_PR / INPUT_BRANCH)
#   - otherwise: all branches listed in the BRANCHES file, plus open PRs
#     on the source repo with activity in the last PR_ACTIVITY_WINDOW_DAYS
#
# Anything already published as a release in this repo is skipped.
# Writes `matrix` (JSON, {include: [...]}) and `any` (true/false) to
# GITHUB_OUTPUT.

set -euo pipefail

SOURCE_REPO=${SOURCE_REPO:-nextflow-io/nextflow}
PR_ACTIVITY_WINDOW_DAYS=${PR_ACTIVITY_WINDOW_DAYS:-7}

candidates='[]'

# args: kind channel ref sha
add_candidate() {
  local kind=$1 channel=$2 ref=$3 sha=$4
  local base version tag
  base=$(gh api "repos/$SOURCE_REPO/contents/VERSION?ref=$sha" --jq .content | base64 -d | tr -d '[:space:]')
  version="${base}-${channel}-${sha:0:7}"
  tag="v${version}"
  if gh api "repos/$GITHUB_REPOSITORY/releases/tags/$tag" --silent >/dev/null 2>&1; then
    echo "skip  $channel: $tag already published"
    return 0
  fi
  echo "build $channel: $version"
  candidates=$(jq -c \
    --arg kind "$kind" --arg channel "$channel" --arg ref "$ref" \
    --arg sha "$sha" --arg version "$version" \
    '. + [{kind:$kind, channel:$channel, ref:$ref, sha:$sha, version:$version}]' \
    <<< "$candidates")
}

add_branch() {
  local branch=$1 sha channel
  sha=$(gh api "repos/$SOURCE_REPO/branches/$branch" --jq .commit.sha)
  channel=$(printf '%s' "$branch" | tr -c 'a-zA-Z0-9' '-')
  add_candidate branch "$channel" "$sha" "$sha"
}

add_pr() {
  local num=$1 sha=${2:-}
  [ -n "$sha" ] || sha=$(gh api "repos/$SOURCE_REPO/pulls/$num" --jq .head.sha)
  add_candidate pr "pr-${num}" "refs/pull/${num}/head" "$sha"
}

if [ -n "${INPUT_PR:-}" ]; then
  add_pr "$INPUT_PR"
elif [ -n "${INPUT_BRANCH:-}" ]; then
  add_branch "$INPUT_BRANCH"
else
  # tracked branches
  while read -r b; do
    if [ -n "$b" ] && [ "${b:0:1}" != '#' ]; then
      add_branch "$b"
    fi
  done < BRANCHES

  # open PRs with recent activity
  cutoff=$(date -u -d "-${PR_ACTIVITY_WINDOW_DAYS} days" +%Y-%m-%dT%H:%M:%SZ)
  mapfile -t prs < <(gh api "repos/$SOURCE_REPO/pulls?state=open&sort=updated&direction=desc&per_page=100" \
    --jq ".[] | select(.updated_at >= \"$cutoff\") | \"\(.number) \(.head.sha)\"")
  for entry in "${prs[@]}"; do
    add_pr $entry
  done
fi

count=$(jq length <<< "$candidates")
echo "-> $count build(s) needed"
echo "matrix={\"include\":$candidates}" >> "$GITHUB_OUTPUT"
[ "$count" -gt 0 ] && echo "any=true" >> "$GITHUB_OUTPUT" || echo "any=false" >> "$GITHUB_OUTPUT"
