# =============================================================================
# ztunnel-testbed - Local curl-client image (curlimages/curl compatible)
# =============================================================================
# Includes curl for HTTP requests, sleeps to keep pod running
# =============================================================================

FROM alpine:3.19
RUN apk add --no-cache curl
# No entrypoint - use command in manifests: ["sleep", "infinity"]
