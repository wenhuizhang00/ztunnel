# =============================================================================
# ztunnel-testbed - Local fortio image (fortio/fortio compatible)
# =============================================================================
# Downloads fortio binary from GitHub releases. BUILD_ARCH: amd64 | arm64
# =============================================================================

ARG FORTIO_VERSION=1.70.0
ARG TARGETARCH=amd64
FROM alpine:3.19 AS builder
ARG FORTIO_VERSION
ARG TARGETARCH
RUN apk add --no-cache curl
WORKDIR /tmp
RUN arch="${TARGETARCH}" && \
    curl -sL "https://github.com/fortio/fortio/releases/download/v${FORTIO_VERSION}/fortio_${FORTIO_VERSION}_linux_${arch}.tar.gz" -o fortio.tar.gz && \
    tar xzf fortio.tar.gz && \
    mv fortio_*/fortio /fortio && \
    chmod +x /fortio

FROM alpine:3.19
COPY --from=builder /fortio /usr/local/bin/fortio
# No entrypoint - use command in manifests: ["sleep", "infinity"]
