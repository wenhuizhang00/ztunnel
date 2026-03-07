#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Image Configuration
# =============================================================================
# Set USE_LOCAL_IMAGES=1 or IMAGE_REGISTRY to use local-built images.
# Run make build-images first when using local images.
# =============================================================================

# Registry for local images (default when USE_LOCAL_IMAGES=1)
export IMAGE_REGISTRY="${IMAGE_REGISTRY:-localhost/ztunnel-testbed}"

# Individual image names (substituted in manifests)
# When USE_LOCAL_IMAGES=1, uses ${IMAGE_REGISTRY}/<name>:latest
# Otherwise uses upstream images
if [[ "${USE_LOCAL_IMAGES:-0}" == "1" ]]; then
  export HTTP_ECHO_IMAGE="${HTTP_ECHO_IMAGE:-${IMAGE_REGISTRY}/http-echo:latest}"
  export CURL_IMAGE="${CURL_IMAGE:-${IMAGE_REGISTRY}/curl-client:latest}"
  export FORTIO_IMAGE="${FORTIO_IMAGE:-${IMAGE_REGISTRY}/fortio:latest}"
else
  export HTTP_ECHO_IMAGE="${HTTP_ECHO_IMAGE:-hashicorp/http-echo:latest}"
  export CURL_IMAGE="${CURL_IMAGE:-curlimages/curl:latest}"
  export FORTIO_IMAGE="${FORTIO_IMAGE:-fortio/fortio:latest}"
fi
