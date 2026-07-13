# Stage 1: Build Stage
FROM golang:1.21-alpine AS builder
WORKDIR /app

# Copy go.mod and go.sum 
COPY go.mod go.sum ./
# Ignore missing checksum errors for the example
RUN go mod download || true 

COPY . .
# Build static binary without C bindings for performance and size
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/bin/main ./cmd/api/main.go

# Stage 2: Production Stage
FROM alpine:3.18
# Install timezone and CA certificates for secure connections
RUN apk --no-cache add ca-certificates tzdata
WORKDIR /root/

# Copy binary from builder
COPY --from=builder /app/bin/main .

EXPOSE 8080
CMD ["./main"]
