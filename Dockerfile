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

WORKDIR /swift-event

# Copy source code. The working-directory name MUST match the SPM package
# identity (`swift-event`) so Examples/LinuxConsumerProbe — which depends
# on the parent via `path: "../.."` — can resolve `package: "swift-event"`
# in its product references.
COPY . .

# Verify Swift version
RUN swift --version

# Build and test the main package.
RUN swift test

# External-consumer regression coverage. Builds a separate SPM package
# that consumes swift-event from outside the parent's resolution graph,
# exercising the libevent modulemap from C++, plain Swift, and Swift
# under C++ interop. Catches modulemap regressions that would otherwise
# only surface in downstream packages like swift-bitcoin.
RUN cd Examples/LinuxConsumerProbe && swift build

CMD ["swift", "test"]
