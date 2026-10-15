# oss-journey-container

A Java 25 devcontainer image (based on `mcr.microsoft.com/devcontainers/java:3-25-trixie`) with
everything the [Vaadin VS Code extension](https://marketplace.visualstudio.com/items?itemName=vaadin.vaadin-vscode)
needs for **Debug using Hotswap Agent** already installed. The extension then has nothing left to
download, so it no longer runs into GitHub API rate limits when a container starts.

## What the extension downloads, and what this image pre-installs

From reading the extension's source (v1.1.8, `out/helpers/hotswap.js` and `jetbrainsUtil.js`):

- **On every activation**, the extension compares `~/.vaadin/vscode-plugin/hotswap-agent.jar` with
  the jar it bundles. If the jar is missing or a different version, it runs setup in "quiet" mode.
  Quiet setup always makes two calls to the unauthenticated `api.github.com` releases API for
  JetBrainsRuntime (the 60 requests/hour limit). It then downloads and extracts the JBR tarball,
  unless `~/.vaadin/jdk/<tarball name>/` already exists. A fresh container never has the jar, so
  every new container went through this.
- The **Debug (hotswap)** code lens runs the same quiet setup when the project has no
  `Debug using Hotswap Agent` launch configuration yet.
- The **Vaadin: Setup Hotswap Agent** command lists existing JetBrains runtimes from `~/.vaadin/jdk`
  and the standard JDK locations. Choosing one of those needs no network access.

The image installs:

| Path | What |
| --- | --- |
| `/home/vscode/.vaadin/vscode-plugin/hotswap-agent.jar` | Taken from the same extension version's VSIX (from open-vsx), so the activation check passes |
| `/home/vscode/.vaadin/jdk/jbrsdk-<ver>-linux-<arch>-<build>/` | JetBrains Runtime SDK (checksum verified), under the directory name the extension expects |
| `/opt/jbr` (and `$JBR_HOME`) | Symlink to that JBR, for use in a `launch.json` |

The default JDK (`JAVA_HOME`) is still Microsoft OpenJDK. JBR is only used for the hotswap debug launch.

Build arguments (defaults in the `Dockerfile`):

- `VAADIN_VSCODE_VERSION`: the extension version the jar comes from. **Pin the same version in
  devcontainer.json**, otherwise an extension update brings a new jar and the download is back.
- `JBR_VERSION` / `JBR_BUILD`: the JBR release. Keep it at the release the extension considers
  "latest". That is the last non-prerelease tag in plain string order, not the newest release:
  for example, `25.0.4b508.27` comes after `25.0.4.1b635.72`. `test/test.sh` warns when the two differ.

## Testing

```sh
test/test.sh            # builds oss-journey-container:dev and tests it
test/test.sh some/image # tests an existing image
```

Every check runs in the container as `vscode` with `--network none`:

1. **Layout**: JBR is in `~/.vaadin/jdk` under the expected name, and its `release` file names
   JetBrains as the implementor (the extension filters on this). It supports
   `-XX:+AllowEnhancedClassRedefinition`. The agent jar's `Implementation-Version` matches the
   extension's bundled jar, and the `vscode` user owns `~/.vaadin`.
2. **Hotswap**: starts a small app with exactly the `vmArgs` the extension writes into
   `launch.json`. It then recompiles a class with a *new method* added and waits for the running
   app to use it.
3. **Control**: runs the same reload on the stock JDK and expects it to fail with
   `attempted to add a method`. This shows step 2 really depends on JBR.
4. **JBR pin**: warns if the pinned JBR is no longer the release the extension would pick (this
   step needs network access).

### Manual test in VS Code

This is the end-to-end check with the real extension:

1. Build the image locally with `docker build -t oss-journey-container:dev .`, or use a published `pr-<number>` tag
2. In an `oss-journey` checkout (`devcontainer-java` branch), point `.devcontainer/devcontainer.json`
   at the local image and pin the extension:
   ```jsonc
   "image": "oss-journey-container:dev",
   "customizations": { "vscode": { "extensions": [
       "vscjava.vscode-java-pack",
       "vaadin.vaadin-vscode@1.1.8"
   ] } }
   ```
3. Run **Dev Containers: Rebuild and Reopen in Container**. No "Downloading JetBrains Runtime..."
   notification should appear.
4. Run **Vaadin: Setup Hotswap Agent** and choose the JBR from `/home/vscode/.vaadin/jdk/...` in
   the list (don't choose "Download"). Then run **Debug using Hotswap Agent**, edit a view and
   save; the change should be applied without a restart.

To avoid the quiet setup (and its GitHub API calls) completely, commit the launch configuration in
the project, with `"javaExec": "/opt/jbr/bin/java"`, so the code lens finds it.

## Published images

The [Image workflow](.github/workflows/image.yml) builds `linux/amd64` and `linux/arm64` on native
runners. It runs `test/test.sh` on each and publishes a multi-arch image to
`ghcr.io/petrixh/oss-journey-container`:

| Event | Tags |
| --- | --- |
| Pull request to `main` | `pr-<number>`, `sha-<head commit>` |
| Push to `main` | `latest`, `sha-<commit>` |
| Manual run on another branch | `<branch name>`, `sha-<commit>` |

PRs from forks are built and tested, but not published.

Use it in a project's `.devcontainer/devcontainer.json`:

```jsonc
"image": "ghcr.io/petrixh/oss-journey-container:latest",
"customizations": { "vscode": { "extensions": [
    "vscjava.vscode-java-pack",
    "vaadin.vaadin-vscode@1.1.8"
] } }
```

## Keeping it up to date

- **Dependabot** updates the base image digest and the GitHub Actions.
- The **[Update versions](.github/workflows/update-versions.yml)** workflow runs every Monday (or
  manually). It runs [`scripts/update-versions.sh`](scripts/update-versions.sh), which bumps
  `JBR_VERSION`/`JBR_BUILD` to the release the extension would pick and `VAADIN_VSCODE_VERSION` to
  the latest version on open-vsx. If anything changed, it opens or updates a PR from
  `deps/jbr-and-extension`. PRs opened by Actions don't trigger other workflows, so it starts the
  Image workflow on that branch itself, which publishes `:deps-jbr-and-extension`.

  This needs **Settings → Actions → General → Allow GitHub Actions to create and approve pull
  requests** to be enabled.
