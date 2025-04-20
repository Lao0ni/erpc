# syntax=docker/dockerfile:1.4

# ---------------------------------------------------------------------------
# Stage 1: Build Go Binary
# ---------------------------------------------------------------------------
    FROM golang:1.23-alpine AS go-builder

    # Arguments for versioning
    ARG VERSION
    ARG COMMIT_SHA
    
    WORKDIR /root
    
    # Cache Go modules
    COPY go.mod go.sum ./
    RUN go mod download
    
    # Copy the full source and build
    COPY . .
    ENV CGO_ENABLED=0 \
        GOOS=linux \
        LDFLAGS="-w -s -X common.ErpcVersion=${VERSION} -X common.ErpcCommitSha=${COMMIT_SHA}"
    RUN go build -v -ldflags="$LDFLAGS" -a -installsuffix cgo -o erpc-server ./cmd/erpc/main.go \
        && go build -v -ldflags="$LDFLAGS" -a -installsuffix cgo -tags pprof -o erpc-server-pprof ./cmd/erpc/*.go
    
    # ---------------------------------------------------------------------------
    # Stage 2: Prepare PNPM (core)
    # ---------------------------------------------------------------------------
    FROM node:20-alpine AS ts-core
    RUN npm install -g pnpm
    
    # ---------------------------------------------------------------------------
    # Stage 3: Install Dev Dependencies + Build TS SDK
    # ---------------------------------------------------------------------------
    FROM ts-core AS ts-dev
    # Ensure build arg for Railway service ID
    ARG RAILWAY_SERVICE_ID
    
    WORKDIR /temp/dev
    RUN mkdir -p typescript
    
    # Copy TS config and package files
    COPY typescript/config ./typescript/config
    COPY pnpm* ./
    COPY package.json ./
    
    # Simple test to confirm Dockerfile is being parsed
    RUN echo "👷‍♂️ ts-dev stage is running with RAILWAY_SERVICE_ID=${RAILWAY_SERVICE_ID}"
    
    # Install & build, using hard‑coded cache ID (replace SERVICE_ID below)
    RUN --mount=type=cache,id=pnpm-store-dev,target=/pnpm/store-dev \
        pnpm install --store-dir /pnpm/store-dev --frozen-lockfile
    RUN pnpm build
    
    # ---------------------------------------------------------------------------
    # Stage 4: Install Prod Dependencies
    # ---------------------------------------------------------------------------
    FROM ts-core AS ts-prod
    ARG RAILWAY_SERVICE_ID
    WORKDIR /temp/prod
    RUN mkdir -p typescript
    
    COPY typescript/config ./typescript/config
    COPY pnpm* ./
    COPY package.json ./
    
    RUN echo "🛠 ts-prod stage is running with RAILWAY_SERVICE_ID=${RAILWAY_SERVICE_ID}"
    
    # Install prod only, using hard‑coded cache ID
    RUN --mount=type=cache,id=pnpm-store-prod,target=/pnpm/store-prod \
        pnpm install --store-dir /pnpm/store-prod --prod --frozen-lockfile
    
    # ---------------------------------------------------------------------------
    # Stage 5: Final Image
    # ---------------------------------------------------------------------------
    FROM debian:stable-slim AS final
    WORKDIR /root
    
    # Install CA certs
    RUN apt-get update && \
        apt-get install -y --no-install-recommends ca-certificates && \
        rm -rf /var/lib/apt/lists/*
    
    # Copy Go binaries
    COPY --from=go-builder /root/erpc-server .
    COPY --from=go-builder /root/erpc-server-pprof .
    
    # Copy TS outputs
    COPY --from=ts-dev /temp/dev/typescript ./typescript
    COPY --from=ts-prod /temp/prod/node_modules ./node_modules
    
    EXPOSE 8080 6060
    CMD ["/root/erpc-server"]    