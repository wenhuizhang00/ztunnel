# =============================================================================
# ztunnel-testbed - Local http-echo image (hashicorp/http-echo compatible)
# =============================================================================
# Compatible with: -text, -listen, -status-code
# =============================================================================

FROM golang:1.22-alpine AS builder
WORKDIR /build
COPY main.go .
RUN CGO_ENABLED=0 go build -o http-echo .

FROM alpine:3.19
COPY --from=builder /build/http-echo /http-echo
EXPOSE 8080
ENTRYPOINT ["/http-echo"]
