# Dockerfile for testing swift-event on Linux
FROM swift:6.1-jammy

# Install build dependencies
# Note: libbsd-dev no longer needed - using bundled arc4random.c with getrandom() syscall
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        pkg-config \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Copy source code
COPY . .

# Verify Swift version
RUN swift --version

# Build and test
RUN swift test

CMD ["swift", "test"]
