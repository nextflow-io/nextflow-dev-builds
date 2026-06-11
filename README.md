# Nextflow development builds

Automated builds of [Nextflow](https://github.com/nextflow-io/nextflow) from the `master` branch and from open pull requests, published as pre-releases in this repository. **For testing purposes only.** For production, use the regular [Nextflow releases](https://github.com/nextflow-io/nextflow/releases).

## What gets built

A scheduled workflow runs every 30 minutes and builds:

- branches listed in the [`BRANCHES`](BRANCHES) file (currently `master`), whenever there are new commits
- open pull requests on `nextflow-io/nextflow` with activity in the last 7 days, whenever there are new commits

Each build is published as a pre-release named after its version, for example `26.04.3-master-0285c3b` or `26.04.3-pr-7123-adcf19a`. The version is the Nextflow base version plus the branch or PR, plus the short commit hash. Old builds are pruned automatically: closed PR builds are deleted, and only the most recent builds are kept per branch and PR.

## Using a dev build

### With an existing Nextflow installation

The standard Nextflow launcher can download any of these builds directly. Point `NXF_BASE` at this repository and set `NXF_VER` to the build you want:

```bash
export NXF_BASE=https://github.com/nextflow-io/nextflow-dev-builds/releases/download
export NXF_VER=26.04.3-master-0285c3b   # pick a version from the Releases page
nextflow run hello
```

To get the most recent build of a branch or PR, the [`latest/`](latest/) directory contains a pointer file per channel:

```bash
export NXF_BASE=https://github.com/nextflow-io/nextflow-dev-builds/releases/download
export NXF_VER=$(curl -fsSL https://raw.githubusercontent.com/nextflow-io/nextflow-dev-builds/main/latest/master)
nextflow run hello
```

For a pull request, replace `latest/master` with `latest/pr-<number>`, e.g. `latest/pr-7123`.

To go back to your normal Nextflow version:

```bash
unset NXF_BASE NXF_VER
```

### As a standalone executable

Each release also includes a self-contained `-dist` executable that bundles the launcher and all dependencies. No existing Nextflow installation is needed, only Java:

```bash
curl -fsSL https://github.com/nextflow-io/nextflow-dev-builds/releases/download/v<VERSION>/nextflow-<VERSION>-dist -o nextflow-dev
chmod +x nextflow-dev
./nextflow-dev run hello
```

Every release's notes contain ready-made copy-paste commands for both methods.

## Release assets

| Asset | Description |
|-------|-------------|
| `nextflow-<version>-one.jar` | Fat jar downloaded by the Nextflow launcher (`NXF_BASE` method) |
| `nextflow-<version>-dist` | Self-contained executable (launcher + jar in one file) |
| `nextflow` | The launcher script from that commit, with its default version set to the build |
| `checksums.sha256` | SHA-256 checksums of the assets |
| `meta.json` | Build metadata (source commit, branch or PR, version) |

## Triggering a build manually

Builds for active PRs and tracked branches happen automatically within about 30 minutes of a push. To build something immediately, or to build a PR or branch outside the automatic rules, use the [build workflow](../../actions/workflows/build.yml) with "Run workflow", or the GitHub CLI:

```bash
gh workflow run build.yml -R nextflow-io/nextflow-dev-builds -f pr=7123
gh workflow run build.yml -R nextflow-io/nextflow-dev-builds -f branch=master
```

## Caveats

- Dev builds resolve Nextflow plugins (nf-amazon, nf-tower, etc.) from the plugin registry at runtime, the same way regular releases do. A PR that changes a plugin and bumps its version cannot be fully tested this way, since the new plugin version is not published anywhere. Core changes, which are the vast majority, work fine.
- Builds run only for code hosted in `nextflow-io/nextflow` (branches and PRs targeting it).
- Old builds are deleted by the retention policy, so do not depend on a dev build URL staying around. Pin a regular release for anything that matters.
