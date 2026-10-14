#!/usr/bin/env bash
# Builds the image and checks it has everything the Vaadin VS Code extension's
# hotswap setup needs. The container checks run with networking disabled, so
# anything that would still need a download fails the test.
#
# Usage: test/test.sh [image]   (default: builds oss-journey-container:dev)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${1:-}"
DEV_USER=vscode

if [ -z "$IMAGE" ]; then
    IMAGE=oss-journey-container:dev
    echo "== Building $IMAGE"
    docker build -t "$IMAGE" "$ROOT"
fi

arg_default() {
    sed -n "s/^ARG $1=//p" "$ROOT/Dockerfile"
}
VAADIN_VSCODE_VERSION="$(arg_default VAADIN_VSCODE_VERSION)"

# Version of the hotswap-agent.jar bundled in that extension release
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/vaadin.vsix" \
    "https://open-vsx.org/api/vaadin/vaadin-vscode/${VAADIN_VSCODE_VERSION}/file/vaadin.vaadin-vscode-${VAADIN_VSCODE_VERSION}.vsix"
unzip -p "$TMP/vaadin.vsix" extension/resources/hotswap-agent.jar > "$TMP/agent.jar"
AGENT_VERSION="$(unzip -p "$TMP/agent.jar" META-INF/MANIFEST.MF | sed -n 's/^Implementation-Version: *//p' | tr -d '\r')"

run() {
    docker run --rm --network none -u "$DEV_USER" -v "$ROOT/test:/test:ro" "$@"
}

echo "== Layout (extension $VAADIN_VSCODE_VERSION, hotswap-agent $AGENT_VERSION)"
run "$IMAGE" /test/check-layout.sh "$AGENT_VERSION"

echo "== Hotswap with JetBrains Runtime (offline)"
run "$IMAGE" /test/hotswap/run-in-container.sh /opt/jbr/bin/java

echo "== Control: same reload must fail on the stock JDK"
if run -e ENHANCED=0 "$IMAGE" bash -c '/test/hotswap/run-in-container.sh "$JAVA_HOME/bin/java"' > "$TMP/control.log" 2>&1; then
    echo "  FAIL stock JDK reloaded the class too, the test is not testing JBR"
    exit 1
fi
grep -q "attempted to add a method" "$TMP/control.log" \
    && echo "  ok   stock JDK rejected the change: attempted to add a method" \
    || { cat "$TMP/control.log"; echo "  FAIL control failed for an unexpected reason"; exit 1; }

# Not fatal: the extension's fallback setup looks for a directory named after
# what it considers the latest JBR release (last non-prerelease tag on the first
# API page in string order), so a mismatch only matters if that setup runs.
echo "== JBR pin vs the extension's idea of the latest release"
latest_tag="$(curl -fsS https://api.github.com/repos/JetBrains/JetBrainsRuntime/releases 2>/dev/null \
    | python3 -c 'import json,sys; r=[x["tag_name"] for x in json.load(sys.stdin) if not x["prerelease"]]; print(sorted(r)[-1])' 2>/dev/null || true)"
pinned_tag="jbr-release-$(arg_default JBR_VERSION)$(arg_default JBR_BUILD)"
if [ -z "$latest_tag" ]; then
    echo "  skip could not reach the GitHub API"
elif [ "$latest_tag" = "$pinned_tag" ]; then
    echo "  ok   $pinned_tag is the release the extension picks"
else
    echo "  warn pinned $pinned_tag, the extension picks $latest_tag"
fi

echo "== All checks passed"
