#!/usr/bin/env bash
#
# Publish built artifacts as pre-releases and update the latest/ pointer
# files. Expects the build artifacts in the directory given as the first
# argument (default: artifacts), one sub-directory per build, each
# containing a meta.json describing the build.

set -euo pipefail
shopt -s nullglob

SOURCE_REPO=${SOURCE_REPO:-nextflow-io/nextflow}
ARTIFACTS_DIR=${1:-artifacts}

mkdir -p latest

for dir in "$ARTIFACTS_DIR"/*/; do
  meta="$dir/meta.json"
  [ -f "$meta" ] || continue
  version=$(jq -r .version "$meta")
  channel=$(jq -r .channel "$meta")
  sha=$(jq -r .sha "$meta")
  kind=$(jq -r .kind "$meta")
  tag="v$version"

  if [ "$kind" = pr ]; then
    prnum="${channel#pr-}"
    source_desc="pull request [#${prnum}](https://github.com/$SOURCE_REPO/pull/${prnum}), commit"
  else
    source_desc="branch \`${channel}\`, commit"
  fi

  notes=$(cat <<EOF
Automated development build of Nextflow. **For testing purposes only.**

Built from ${source_desc} [\`${sha:0:7}\`](https://github.com/$SOURCE_REPO/commit/${sha}) by [this workflow run](${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}).

### Use with an existing Nextflow installation

\`\`\`bash
NXF_BASE=https://github.com/${GITHUB_REPOSITORY}/releases/download \\
NXF_VER=${version} \\
nextflow run hello
\`\`\`

Set inline as above, nothing persists in your environment. Do not run \`self-update\` with \`NXF_BASE\` set.

### Or as a standalone executable (no Nextflow required)

\`\`\`bash
curl -fsSL https://github.com/${GITHUB_REPOSITORY}/releases/download/${tag}/nextflow-${version}-dist -o nextflow-dev
chmod +x nextflow-dev
./nextflow-dev run hello
\`\`\`
EOF
  )

  if gh release view "$tag" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
    echo "release $tag already exists, skipping"
  else
    gh release create "$tag" \
      --repo "$GITHUB_REPOSITORY" \
      --prerelease \
      --title "$version" \
      --notes "$notes" \
      "$dir"/*
    echo "published $tag"
  fi

  echo "$version" > "latest/$channel"
done

# update the latest-version pointer files
git add latest
if ! git diff --cached --quiet; then
  git -c user.name='github-actions[bot]' \
      -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
      commit -m "Update latest build pointers"
  git push
fi
