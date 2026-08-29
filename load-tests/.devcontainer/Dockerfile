# Dev container image for running Gatling load tests.
#
# Based on Microsoft's Java 21 dev container, which includes:
# - JDK 21 (Eclipse Temurin)
# - Gradle (via the wrapper in the project)
# - Standard dev tools (git, curl, etc.)
#
# We add Coursier (the Scala package manager) for Scala tooling support
# in VS Code via the Metals extension.

FROM mcr.microsoft.com/devcontainers/java:21

# Install Coursier for Scala tooling (used by the Metals VS Code extension).
# Note: the Scala compiler itself is managed by Gradle via the Gatling plugin,
# so we only need Coursier for IDE support.
#
# Pinned to a specific version with checksum verification to prevent
# supply chain attacks via mutable "latest" release URLs.
ARG COURSIER_VERSION=v2.1.24
ARG COURSIER_SHA256=1517a0b6c4b9608dc45da8f34bc8290707ed50104ee92662f57808d2c012be54
RUN curl -fL "https://github.com/coursier/coursier/releases/download/${COURSIER_VERSION}/cs-x86_64-pc-linux.gz" \
      | gzip -d > /usr/local/bin/cs \
    && echo "${COURSIER_SHA256}  /usr/local/bin/cs" | sha256sum -c - \
    && chmod +x /usr/local/bin/cs
