# Nextflow development builds

Automated builds of [Nextflow](https://github.com/nextflow-io/nextflow) from the `master` branch and from open pull requests, published as pre-releases in this repository. **For testing purposes only.** For production, use the regular [Nextflow releases](https://github.com/nextflow-io/nextflow/releases).

## What gets built

A scheduled workflow runs every 30 minutes and builds:

- branches listed in the [`BRANCHES`](BRANCHES) file (currently `master`), whenever there are new commits
- open pull requests on `nextflow-io/nextflow` with activity in the last 7 days, whenever there are new commits

Each build is published as a pre-release named after its version, for example `26.04.3-master-0285c3b` or `26.04.3-pr-7123-adcf19a`. The version is the Nextflow base version plus the branch or PR, plus the short commit hash. Old builds are pruned automatically: closed PR builds are deleted, and only the most recent builds are kept per branch and PR.

## Using a dev build

### With an existing Nextflow installation

The standard Nextflow launcher can download any of these builds directly. Point `NXF_BASE` at this repository and set `NXF_VER` to the build you want. Setting the variables inline means nothing persists in your environment, and your next plain `nextflow` invocation behaves exactly as before:

```bash
NXF_BASE=https://github.com/nextflow-io/nextflow-dev-builds/releases/download \
NXF_VER=26.04.3-master-0285c3b \
nextflow run hello
```

Pick a version from the [Releases page](../../releases), or get the most recent build of a branch or PR from the pointer files in the [`latest/`](latest/) directory:

```bash
export NXF_BASE=https://github.com/nextflow-io/nextflow-dev-builds/releases/download
export NXF_VER=$(curl -fsSL https://raw.githubusercontent.com/nextflow-io/nextflow-dev-builds/master/latest/master)
nextflow run hello
```

For a pull request, replace `latest/master` with `latest/pr-<number>`, e.g. `latest/pr-7123`.

If you do this often, add this small function to your shell profile:

```bash
nxf-dev() {
  export NXF_BASE=https://github.com/nextflow-io/nextflow-dev-builds/releases/download
  export NXF_VER=$(curl -fsSL "https://raw.githubusercontent.com/nextflow-io/nextflow-dev-builds/master/latest/${1:-master}")
  echo "Using Nextflow dev build: $NXF_VER"
}
```

Then switching to a dev build is just:

```bash
nxf-dev master      # latest master build
nxf-dev pr-7123     # latest build of PR #7123
nextflow run hello
unset NXF_BASE NXF_VER   # back to normal
```

If you exported the variables, go back to your normal Nextflow version with:

```bash
unset NXF_BASE NXF_VER
```

> [!WARNING]
> Do not run `nextflow self-update` while `NXF_BASE` is set. Self-update replaces the launcher script itself, and would leave you with the dev build as your default version even after unsetting the variables. If that happens, restore the regular launcher with `unset NXF_BASE NXF_VER` followed by `nextflow self-update`.

The downloaded jars are cached in `~/.nextflow/framework/<version>/`. They are inert when not selected, but you can delete them to reclaim space.

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
