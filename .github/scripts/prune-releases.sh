#!/usr/bin/env bash
#
# Prune dev build releases:
#   - delete builds for pull requests that have been closed or merged
#   - keep only the newest KEEP_PER_PR / KEEP_PER_BRANCH builds per
#     PR / branch, across Nextflow versions
#   - remove latest/ pointer files whose release no longer exists
# A failed delete is retried on the next run instead of stopping this one.

set -euo pipefail

SOURCE_REPO=${SOURCE_REPO:-nextflow-io/nextflow}
KEEP_PER_BRANCH=${KEEP_PER_BRANCH:-30}
KEEP_PER_PR=${KEEP_PER_PR:-3}

releases=$(gh api "repos/$GITHUB_REPOSITORY/releases" --paginate | jq -s 'add | map({tag: .tag_name, created: .created_at}) | sort_by(.created) | reverse')
tags=$(jq -r '.[].tag' <<< "$releases")
echo "found $(jq length <<< "$releases") releases"

declare -A deleted
failures=0

delete_release() {
  local tag=$1 reason=$2
  echo "deleting $tag ($reason)"
  if gh release delete "$tag" --repo "$GITHUB_REPOSITORY" --yes --cleanup-tag; then
    deleted[$tag]=1
  else
    echo "::warning::failed to delete $tag"
    failures=$((failures + 1))
  fi
}

# cache of PR states so we only query each PR once
declare -A pr_state

# how many releases we have kept so far per group, newest first
declare -A group_count

for tag in $tags; do
  # closed-PR builds are always deleted
  if [[ "$tag" =~ -pr-([0-9]+)-[0-9a-f]{7}$ ]]; then
    prnum="${BASH_REMATCH[1]}"
    if [ -z "${pr_state[$prnum]:-}" ]; then
      pr_state[$prnum]=$(gh api "repos/$SOURCE_REPO/pulls/$prnum" --jq .state || echo unknown)
    fi
    if [ "${pr_state[$prnum]}" = closed ]; then
      delete_release "$tag" "PR #$prnum is closed"
      continue
    fi
    keep=$KEEP_PER_PR
  else
    keep=$KEEP_PER_BRANCH
  fi

  # group by branch or PR, not version: tags are v<version>-<channel>-<sha7>
  if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-edge)?-(.+)-[0-9a-f]{7}$ ]]; then
    group=${BASH_REMATCH[2]}
  else
    group=${tag%-*}
  fi
  n=$(( ${group_count[$group]:-0} + 1 ))
  group_count[$group]=$n
  if [ "$n" -gt "$keep" ]; then
    delete_release "$tag" "retention: keeping newest $keep for $group"
  fi
done

for f in latest/*; do
  tag="v$(cat "$f")"
  if ! grep -qxF "$tag" <<< "$tags" || [ -n "${deleted[$tag]:-}" ]; then
    echo "removing $f ($tag no longer exists)"
    rm "$f"
  fi
done

git add -A latest
if ! git diff --cached --quiet; then
  git -c user.name='github-actions[bot]' \
      -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
      commit -m "Remove stale build pointers"
  git push
fi

if [ "$failures" -gt 0 ]; then
  echo "::error::$failures release(s) could not be deleted, retrying on the next run"
  exit 1
fi
