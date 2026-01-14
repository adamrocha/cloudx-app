FROM golang:1.25-alpine AS builder

WORKDIR /build
COPY go.mod go.sum ./
COPY *.go ./

# Explicitly build for ARM64
RUN CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o server .

FROM alpine:latest
RUN apk --no-cache add ca-certificates wget

# Create a non-root user
RUN addgroup -g 10000 appgroup && \
    adduser -D -u 10000 -G appgroup appuser

# Use the app user's home directory
WORKDIR /home/appuser
COPY --from=builder /build/server .
RUN chown appuser:appgroup server && \
    chmod +x server

# Switch to non-root user
USER appuser

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8091/healthz || exit 1

CMD ["./server"]