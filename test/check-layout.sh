#!/usr/bin/env bash
# Runs inside the container as the dev user: checks that the files are where
# the Vaadin VS Code extension looks for them, so it won't download anything.
#
# Usage: check-layout.sh <expected hotswap-agent Implementation-Version>
set -euo pipefail

EXPECTED_AGENT_VERSION="$1"
VAADIN_HOME="$HOME/.vaadin"
FAILED=0

ok()   { echo "  ok   $*"; }
fail() { echo "  FAIL $*"; FAILED=1; }

echo "Checking $VAADIN_HOME as $(id -un)"

# The extension extracts JBR to ~/.vaadin/jdk/<tarball name without .tar.gz>
# and only lists runtimes whose release file says IMPLEMENTOR="...JetBrains..."
jdks=("$VAADIN_HOME"/jdk/jbrsdk-*)
if [ "${#jdks[@]}" -eq 1 ] && [ -d "${jdks[0]}" ]; then
    jbr="${jdks[0]}"
    ok "JBR found: $jbr"
    grep -q '^IMPLEMENTOR=".*JetBrains.*"' "$jbr/release" \
        && ok "release file: $(grep ^IMPLEMENTOR= "$jbr/release")" \
        || fail "release file does not name JetBrains as IMPLEMENTOR"
    "$jbr/bin/java" -XX:+AllowEnhancedClassRedefinition -version > /dev/null 2>&1 \
        && ok "java supports -XX:+AllowEnhancedClassRedefinition ($(grep ^JAVA_VERSION= "$jbr/release"))" \
        || fail "java does not support -XX:+AllowEnhancedClassRedefinition"
    [ "$(readlink -f /opt/jbr)" = "$(readlink -f "$jbr")" ] \
        && ok "/opt/jbr -> $jbr" || fail "/opt/jbr does not point to $jbr"
else
    fail "expected exactly one $VAADIN_HOME/jdk/jbrsdk-* directory, found: ${jdks[*]}"
fi

# On activation the extension re-runs setup (and downloads) unless this jar's
# Implementation-Version equals the one bundled in the extension.
agent="$VAADIN_HOME/vscode-plugin/hotswap-agent.jar"
if [ -f "$agent" ]; then
    version="$(unzip -p "$agent" META-INF/MANIFEST.MF | sed -n 's/^Implementation-Version: *//p' | tr -d '\r')"
    [ "$version" = "$EXPECTED_AGENT_VERSION" ] \
        && ok "hotswap-agent.jar version $version matches the extension" \
        || fail "hotswap-agent.jar version '$version', extension bundles '$EXPECTED_AGENT_VERSION'"
else
    fail "$agent missing"
fi

# The extension writes into ~/.vaadin, so the dev user must own it
others="$(find "$VAADIN_HOME" ! -user "$(id -un)" | head -3)"
[ -z "$others" ] && ok "$VAADIN_HOME is owned by $(id -un)" || fail "not owned by $(id -un): $others"

exit "$FAILED"
