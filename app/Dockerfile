FROM golang:1.25-alpine AS builder

WORKDIR /app
COPY . .
RUN go build -o server .

FROM alpine:latest
WORKDIR /root/
COPY --from=builder /app/server .

CMD ["./server"]