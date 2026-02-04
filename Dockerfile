# Code Conclave - AI-Powered Code Review Container
#
# Usage:
#   docker build -t conclave:latest .
#   docker run -v /path/to/repo:/repo conclave:latest -Project /repo -OutputFormat junit -CI

FROM mcr.microsoft.com/powershell:7.4-ubuntu-22.04

LABEL org.opencontainers.image.title="Code Conclave" \
      org.opencontainers.image.description="AI-Powered Code Review with Compliance Mapping" \
      org.opencontainers.image.version="2.0.0" \
      org.opencontainers.image.source="https://github.com/Blb3D/code-conclave"

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /conclave

# Copy application files
COPY cli/ ./cli/
COPY core/ ./core/

# Create directories for output
RUN mkdir -p /output /repo

# Create non-root user for security
RUN useradd -m -s /bin/bash conclave \
    && chown -R conclave:conclave /conclave /output /repo

USER conclave

# Set environment variables
ENV CONCLAVE_HOME=/conclave
ENV PATH="${CONCLAVE_HOME}/cli:${PATH}"

# Default entrypoint
ENTRYPOINT ["pwsh", "/conclave/cli/ccl.ps1"]

# Default to help if no args
CMD ["--help"]
