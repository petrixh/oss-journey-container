# Java 25 devcontainer with everything the Vaadin VS Code extension needs for
# "Debug using Hotswap Agent" pre-installed, so the extension never has to hit
# the GitHub API or download the JetBrains Runtime when the container starts.
#
# The extension (vaadin.vaadin-vscode) looks for:
#   ~/.vaadin/vscode-plugin/hotswap-agent.jar   - must match the jar bundled in
#                                                 the extension, otherwise it
#                                                 re-runs setup on activation
#   ~/.vaadin/jdk/<jbrsdk tarball name>/        - JetBrains Runtime (DCEVM)

# Pinned by digest so Dependabot opens a PR when the tag is republished
FROM mcr.microsoft.com/devcontainers/java:3-25-trixie@sha256:da82e11bce1d8c01f36e1dc559f1aadaa28fcbd3e1356fd0bd9fa100f5b3d75d

# JetBrains Runtime release, see https://github.com/JetBrains/JetBrainsRuntime/releases
# Keep this at the release the extension considers "latest": its fallback setup
# looks for a directory named after that release's tarball and downloads it if
# missing. Note it picks the last non-prerelease tag in *string* order (from the
# first page of the API), not the newest one: e.g. jbr-release-25.0.4b508.27
# sorts after jbr-release-25.0.4.1b635.72. test/test.sh reports a mismatch.
ARG JBR_VERSION=25.0.4
ARG JBR_BUILD=b508.27
# Vaadin VS Code extension version whose bundled hotswap-agent.jar is installed.
ARG VAADIN_VSCODE_VERSION=1.1.8
ARG USERNAME=vscode
# Set by BuildKit: amd64 or arm64
ARG TARGETARCH

RUN set -eux; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64) jbr_arch=x64 ;; \
        arm64) jbr_arch=aarch64 ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    user_home="$(getent passwd "${USERNAME}" | cut -d: -f6)"; \
    vaadin_home="${user_home}/.vaadin"; \
    jbr_name="jbrsdk-${JBR_VERSION}-linux-${jbr_arch}-${JBR_BUILD}"; \
    tmp="$(mktemp -d)"; \
    \
    # JetBrains Runtime, extracted the same way the extension does it
    curl -fsSL --retry 5 -o "${tmp}/${jbr_name}.tar.gz" \
        "https://cache-redirector.jetbrains.com/intellij-jbr/${jbr_name}.tar.gz"; \
    curl -fsSL --retry 5 -o "${tmp}/${jbr_name}.tar.gz.checksum" \
        "https://cache-redirector.jetbrains.com/intellij-jbr/${jbr_name}.tar.gz.checksum"; \
    (cd "${tmp}" && sha512sum -c "${jbr_name}.tar.gz.checksum"); \
    mkdir -p "${vaadin_home}/jdk"; \
    tar -xzf "${tmp}/${jbr_name}.tar.gz" -C "${vaadin_home}/jdk"; \
    test -x "${vaadin_home}/jdk/${jbr_name}/bin/java"; \
    ln -s "${vaadin_home}/jdk/${jbr_name}" /opt/jbr; \
    \
    # hotswap-agent.jar bundled in the extension (open-vsx has no GitHub-style rate limits)
    curl -fsSL --retry 5 -o "${tmp}/vaadin.vsix" \
        "https://open-vsx.org/api/vaadin/vaadin-vscode/${VAADIN_VSCODE_VERSION}/file/vaadin.vaadin-vscode-${VAADIN_VSCODE_VERSION}.vsix"; \
    mkdir -p "${vaadin_home}/vscode-plugin"; \
    unzip -p "${tmp}/vaadin.vsix" extension/resources/hotswap-agent.jar \
        > "${vaadin_home}/vscode-plugin/hotswap-agent.jar"; \
    unzip -tq "${vaadin_home}/vscode-plugin/hotswap-agent.jar"; \
    \
    chown -R "${USERNAME}:${USERNAME}" "${vaadin_home}"; \
    rm -rf "${tmp}"

ENV JBR_HOME=/opt/jbr

# Note: no devcontainer.metadata LABEL here, it would replace (not extend) the
# base image's metadata. Pin the extension in devcontainer.json instead:
#   "vaadin.vaadin-vscode@<VAADIN_VSCODE_VERSION>"
LABEL org.opencontainers.image.source=https://github.com/petrixh/oss-journey-container \
      org.opencontainers.image.description="Java 25 devcontainer with JetBrains Runtime and hotswap-agent pre-installed for the Vaadin VS Code extension"
