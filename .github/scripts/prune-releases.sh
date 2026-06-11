#!/usr/bin/env bash
#
# Prune dev build releases:
#   - delete builds for pull requests that have been closed or merged
#   - keep only the newest KEEP_PER_PR / KEEP_PER_BRANCH builds per
#     PR / branch (builds are grouped by tag minus the -<sha7> suffix)

set -euo pipefail

SOURCE_REPO=${SOURCE_REPO:-nextflow-io/nextflow}
KEEP_PER_BRANCH=${KEEP_PER_BRANCH:-30}
KEEP_PER_PR=${KEEP_PER_PR:-3}

releases=$(gh api "repos/$GITHUB_REPOSITORY/releases" --paginate | jq -s 'add | map({tag: .tag_name, created: .created_at}) | sort_by(.created) | reverse')
count=$(jq length <<< "$releases")
echo "found $count releases"

delete_release() {
  local tag=$1 reason=$2
  echo "deleting $tag ($reason)"
  gh release delete "$tag" --repo "$GITHUB_REPOSITORY" --yes --cleanup-tag
}

# cache of PR states so we only query each PR once
declare -A pr_state

# how many releases we have kept so far per group, newest first
declare -A group_count

for tag in $(jq -r '.[].tag' <<< "$releases"); do
  # closed-PR builds are always deleted
  if [[ "$tag" =~ -pr-([0-9]+)-[0-9a-f]{7}$ ]]; then
    prnum="${BASH_REMATCH[1]}"
    if [ -z "${pr_state[$prnum]:-}" ]; then
      pr_state[$prnum]=$(gh api "repos/$SOURCE_REPO/pulls/$prnum" --jq .state || echo unknown)
    fi
    if [ "${pr_state[$prnum]}" = closed ]; then
      delete_release "$tag" "PR #$prnum is closed"
      rm -f "latest/pr-$prnum"
      continue
    fi
    keep=$KEEP_PER_PR
  else
    keep=$KEEP_PER_BRANCH
  fi

  # retention per group: strip the trailing -<sha7> to group builds of the
  # same branch or PR together
  group="${tag%-*}"
  n=$(( ${group_count[$group]:-0} + 1 ))
  group_count[$group]=$n
  if [ "$n" -gt "$keep" ]; then
    delete_release "$tag" "retention: keeping newest $keep for $group"
  fi
done

# commit any pointer file removals
git add -A latest 2>/dev/null || true
if ! git diff --cached --quiet; then
  git -c user.name='github-actions[bot]' \
      -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
      commit -m "Remove pointers for closed PRs"
  git push
fi
