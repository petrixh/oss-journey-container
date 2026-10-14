#!/usr/bin/env bash
# Bumps the JetBrains Runtime and Vaadin VS Code extension versions pinned in
# the Dockerfile (and README) to what the extension would use today.
#
# Prints a Markdown summary of the changes to stdout, nothing if up to date.
# Set GH_TOKEN to avoid the unauthenticated GitHub API rate limit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCKERFILE="$ROOT/Dockerfile"
README="$ROOT/README.md"

arg() {
    sed -n "s/^ARG $1=//p" "$DOCKERFILE"
}
set_arg() {
    sed -i "s/^ARG $1=.*/ARG $1=$2/" "$DOCKERFILE"
}
github() {
    curl -fsSL ${GH_TOKEN:+-H "Authorization: Bearer $GH_TOKEN"} "https://api.github.com/$1"
}

changes=()

# --- JetBrains Runtime ------------------------------------------------------
# Same selection as the extension's jetbrainsUtil.js: first page of releases,
# non-prereleases, last tag by localeCompare, then the JBRSDK .tar.gz row for
# the architecture from the release notes table.
# shellcheck disable=SC2016 # ${...} below is a JavaScript template literal
jbr="$(github repos/JetBrains/JetBrainsRuntime/releases | node -e '
    const releases = JSON.parse(require("fs").readFileSync(0)).filter((r) => !r.prerelease);
    releases.sort((a, b) => a.tag_name.localeCompare(b.tag_name));
    const release = releases[releases.length - 1];
    const tarball = (arch) => {
        for (const line of release.body.split("\n")) {
            const parts = line.split("|");
            if (parts.length < 4) continue;
            const url = parts[3].replace(/\[.*]/, "").replace(/[()]/g, "").trim();
            if (parts[1].trim() === arch && parts[2].replace("*", "").trim() === "JBRSDK" && url.endsWith(".tar.gz")) {
                return url.split("/").pop();
            }
        }
        throw new Error(`No JBRSDK tarball for ${arch} in ${release.tag_name}`);
    };
    const m = tarball("linux-x64").match(/^jbrsdk-(.+)-linux-x64-(b[^-]+)\.tar\.gz$/);
    if (!m) throw new Error(`Unexpected tarball name in ${release.tag_name}`);
    if (tarball("linux-aarch64") !== `jbrsdk-${m[1]}-linux-aarch64-${m[2]}.tar.gz`) {
        throw new Error(`linux-aarch64 tarball does not match linux-x64 in ${release.tag_name}`);
    }
    console.log(`${m[1]} ${m[2]} ${release.html_url}`);
')"
read -r jbr_version jbr_build jbr_url <<< "$jbr"
old_jbr="$(arg JBR_VERSION) $(arg JBR_BUILD)"
if [ "$jbr_version $jbr_build" != "$old_jbr" ]; then
    set_arg JBR_VERSION "$jbr_version"
    set_arg JBR_BUILD "$jbr_build"
    changes+=("- JetBrains Runtime: \`${old_jbr/ /\` \`}\` → \`$jbr_version\` \`$jbr_build\` ([release]($jbr_url))")
fi

# --- Vaadin VS Code extension -----------------------------------------------
# The image downloads the VSIX from open-vsx, so only bump to versions there
old_ext="$(arg VAADIN_VSCODE_VERSION)"
ext="$(curl -fsSL https://open-vsx.org/api/vaadin/vaadin-vscode \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)["version"])')"
if [ "$ext" != "$old_ext" ]; then
    set_arg VAADIN_VSCODE_VERSION "$ext"
    sed -i "s/vaadin-vscode@$old_ext/vaadin-vscode@$ext/g" "$README"
    changes+=("- Vaadin VS Code extension: \`$old_ext\` → \`$ext\` ([changelog](https://marketplace.visualstudio.com/items/vaadin.vaadin-vscode/changelog)). Check the hotswap/JBR setup logic didn't change, and update \`vaadin.vaadin-vscode@$ext\` in projects using the image.")
fi

if [ "${#changes[@]}" -gt 0 ]; then
    printf '%s\n' "${changes[@]}"
fi
