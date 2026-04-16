# Code Conclave - AI-Powered Code Review Container
#
# Usage:
#   docker build -t conclave:latest -f docker/Dockerfile .
#   docker run -v /path/to/repo:/repo conclave:latest rc -p /repo --dry-run --ci

FROM python:3.12-slim

LABEL org.opencontainers.image.title="Code Conclave" \
      org.opencontainers.image.description="AI-Powered Code Review with Compliance Mapping" \
      org.opencontainers.image.version="3.0.0" \
      org.opencontainers.image.source="https://github.com/Blb3D/code-conclave"

# Install git (needed for diff-scoping)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy and install package
COPY pyproject.toml .
COPY src/ src/

RUN pip install --no-cache-dir .

# Create non-root user
RUN useradd -m -s /bin/bash conclave \
    && mkdir -p /repo /output \
    && chown -R conclave:conclave /repo /output

USER conclave

# Default entrypoint: the `ccl` CLI
ENTRYPOINT ["ccl"]
CMD ["--help"]
