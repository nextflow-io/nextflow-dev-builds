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
# PRs from forks are always skipped, as is anything already published as a
# release in this repo. Scheduled runs also skip builds that failed in one of
# the last 10 failed runs; a manual dispatch retries them.
# Writes `matrix` (JSON, {include: [...]}) and `any` (true/false) to
# GITHUB_OUTPUT.

set -euo pipefail

SOURCE_REPO=${SOURCE_REPO:-nextflow-io/nextflow}
PR_ACTIVITY_WINDOW_DAYS=${PR_ACTIVITY_WINDOW_DAYS:-7}

pending='[]'
candidates='[]'
failed=''

# args: kind channel ref sha
add_candidate() {
  pending=$(jq -c --arg kind "$1" --arg channel "$2" --arg ref "$3" --arg sha "$4" \
    '. + [{$kind, $channel, $ref, $sha}]' <<< "$pending")
}

add_branch() {
  local branch=$1 sha channel
  sha=$(gh api "repos/$SOURCE_REPO/branches/$branch" --jq .commit.sha)
  channel=$(printf '%s' "$branch" | tr -c 'a-zA-Z0-9' '-')
  add_candidate branch "$channel" "$sha" "$sha"
}

add_pr() {
  local num=$1 sha=${2:-} head_repo=${3:-} info
  if [ -z "$sha" ]; then
    info=$(gh api "repos/$SOURCE_REPO/pulls/$num" --jq '"\(.head.sha) \(.head.repo.full_name)"')
    read -r sha head_repo <<< "$info"
  fi
  # fork PRs would get third-party code published under this org
  if [ "$head_repo" != "$SOURCE_REPO" ]; then
    echo "skip  pr-$num: head is in fork '$head_repo'"
    return 0
  fi
  add_candidate pr "pr-${num}" "refs/pull/${num}/head" "$sha"
}

if [ -n "${INPUT_PR:-}" ]; then
  add_pr "$INPUT_PR"
elif [ -n "${INPUT_BRANCH:-}" ]; then
  add_branch "$INPUT_BRANCH"
else
  # otherwise a broken commit is rebuilt every run until its next push
  failed=$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/build.yml/runs?status=failure&per_page=10" --jq '.workflow_runs[].id' |
    xargs -P 10 -I{} gh api "repos/$GITHUB_REPOSITORY/actions/runs/{}/jobs?per_page=100" \
      --jq '.jobs[] | select(.conclusion == "failure") | .name | ltrimstr("build ")')

  # tracked branches
  while read -r b; do
    if [ -n "$b" ] && [ "${b:0:1}" != '#' ]; then
      add_branch "$b"
    fi
  done < BRANCHES

  # open PRs with recent activity
  cutoff=$(date -u -d "-${PR_ACTIVITY_WINDOW_DAYS} days" +%Y-%m-%dT%H:%M:%SZ)
  mapfile -t prs < <(gh api "repos/$SOURCE_REPO/pulls?state=open&sort=updated&direction=desc&per_page=100" \
    --jq ".[] | select(.updated_at >= \"$cutoff\") | \"\(.number) \(.head.sha) \(.head.repo.full_name)\"")
  for entry in "${prs[@]}"; do
    add_pr $entry
  done
fi

if [ "$pending" != '[]' ]; then
  # every candidate's VERSION file in one request, aliased s0, s1, ...
  query=$(jq -r --arg repo "$SOURCE_REPO" '
    ($repo | split("/")) as [$owner, $name]
    | "query { repository(owner: \"\($owner)\", name: \"\($name)\") { "
      + ([to_entries[] | "s\(.key): object(expression: \"\(.value.sha):VERSION\") { ... on Blob { text } }"] | join(" "))
      + " } }"' <<< "$pending")
  bases=$(gh api graphql -f query="$query" --jq .data.repository)
  # prune deletes tags along with releases, so a tag means published
  published=$(git ls-remote --tags --refs "https://github.com/$GITHUB_REPOSITORY" | sed 's|.*refs/tags/||')

  lines=$(jq -r --argjson bases "$bases" 'to_entries[]
    | "\(.value.kind) \(.value.channel) \(.value.ref) \(.value.sha) \($bases["s\(.key)"].text // "" | gsub("\\s"; ""))"' <<< "$pending")
  while read -r kind channel ref sha base; do
    version="${base}-${channel}-${sha:0:7}"
    # the VERSION file in a PR is attacker-controlled, so only allow safe characters
    if [[ ! "$version" =~ ^[A-Za-z0-9][A-Za-z0-9.\-]*$ ]]; then
      echo "skip  $channel: unsafe version string '$version'"
      continue
    fi
    if grep -qxF "$version" <<< "$failed"; then
      echo "skip  $channel: $version already failed to build"
      continue
    fi
    if grep -qxF "v$version" <<< "$published"; then
      echo "skip  $channel: v$version already published"
      continue
    fi
    echo "build $channel: $version"
    candidates=$(jq -c \
      --arg kind "$kind" --arg channel "$channel" --arg ref "$ref" \
      --arg sha "$sha" --arg version "$version" \
      '. + [{kind:$kind, channel:$channel, ref:$ref, sha:$sha, version:$version}]' \
      <<< "$candidates")
  done <<< "$lines"
fi

count=$(jq length <<< "$candidates")
echo "-> $count build(s) needed"
echo "matrix={\"include\":$candidates}" >> "$GITHUB_OUTPUT"
[ "$count" -gt 0 ] && echo "any=true" >> "$GITHUB_OUTPUT" || echo "any=false" >> "$GITHUB_OUTPUT"
