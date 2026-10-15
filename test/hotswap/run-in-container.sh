#!/usr/bin/env bash
# Runs inside the container: starts a small app with the same JVM arguments the
# Vaadin extension writes into launch.json, swaps in a class with a new method
# and checks that the running JVM picks it up.
#
# Usage: run-in-container.sh <java executable>
# ENHANCED=0 leaves out -XX:+AllowEnhancedClassRedefinition (for stock JDKs,
# used as a negative control: the reload is expected to fail there).
set -euo pipefail

JAVA="$1"
JAVAC="$(dirname "$JAVA")/javac"
AGENT="$HOME/.vaadin/vscode-plugin/hotswap-agent.jar"
SRC="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'kill "$PID" 2>/dev/null || true; rm -rf "$WORK"' EXIT

ENHANCED_FLAG=()
[ "${ENHANCED:-1}" = 1 ] && ENHANCED_FLAG=(-XX:+AllowEnhancedClassRedefinition)

mkdir -p "$WORK/classes"
"$JAVAC" -d "$WORK/classes" "$SRC/src/App.java" "$SRC/src/Greeter.java"
cp "$SRC/src/hotswap-agent.properties" "$WORK/classes/"

# Same vmArgs as vaadin-vscode's updateLaunchConfiguration()
"$JAVA" \
    --add-opens java.base/sun.nio.ch=ALL-UNNAMED \
    --add-opens java.base/java.lang=ALL-UNNAMED \
    --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
    --add-opens java.base/java.io=ALL-UNNAMED \
    --add-opens java.base/sun.security.action=ALL-UNNAMED \
    --add-opens java.desktop/java.beans=ALL-UNNAMED \
    --add-opens java.desktop/com.sun.beans=ALL-UNNAMED \
    --add-opens java.desktop/com.sun.beans.introspect=ALL-UNNAMED \
    --add-opens java.desktop/com.sun.beans.util=ALL-UNNAMED \
    --add-opens java.base/jdk.internal.loader=ALL-UNNAMED \
    "${ENHANCED_FLAG[@]}" \
    -XX:+ClassUnloading \
    -javaagent:"$AGENT" \
    -cp "$WORK/classes" App > "$WORK/out.log" 2>&1 &
PID=$!

wait_for() {
    for _ in $(seq 1 60); do
        grep -q "$1" "$WORK/out.log" && return 0
        kill -0 "$PID" 2>/dev/null || break
        sleep 0.5
    done
    echo "--- app output ---"; cat "$WORK/out.log"; echo "------------------"
    return 1
}

wait_for "greeting=v1"
# Give the agent's file watcher a moment before changing the class
sleep 2
"$JAVAC" -cp "$WORK/classes" -d "$WORK/classes" "$SRC/v2/Greeter.java"
wait_for "greeting=v2+new-method"
echo "hotswap OK: class with an added method was reloaded"
