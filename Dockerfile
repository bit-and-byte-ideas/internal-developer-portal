# Multi-stage Dockerfile for Backstage
# Stage 1: Build
FROM node:20-bookworm AS build

# Install dependencies needed for native modules (better-sqlite3, isolated-vm, etc.)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3 \
    g++ \
    gcc \
    make \
    build-essential \
    git \
    ca-certificates \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy package files
COPY package.json yarn.lock .yarnrc.yml ./
COPY .yarn ./.yarn

# Copy workspace package files
COPY packages/app/package.json ./packages/app/
COPY packages/backend/package.json ./packages/backend/

# Install dependencies (skip build scripts initially to avoid isolated-vm issues)
RUN yarn install --immutable --mode=skip-build

# Rebuild only essential native modules
RUN yarn rebuild better-sqlite3 || true

# Copy source files
COPY . .

# Build all packages (backend and frontend)
# Note: build:all compiles TypeScript and bundles the applications
RUN yarn build:all

# Stage 2: Runtime
FROM node:20-bookworm-slim

# Install runtime dependencies for better-sqlite3
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/*

# Create app directory and user
RUN groupadd -r backstage && useradd -r -g backstage backstage
WORKDIR /app

# Copy built artifacts from build stage
COPY --from=build --chown=backstage:backstage /app/yarn.lock /app/package.json /app/.yarnrc.yml ./
COPY --from=build --chown=backstage:backstage /app/.yarn ./.yarn
COPY --from=build --chown=backstage:backstage /app/packages/backend/dist ./packages/backend/dist
COPY --from=build --chown=backstage:backstage /app/packages/backend/package.json ./packages/backend/

# Copy production dependencies only
COPY --from=build --chown=backstage:backstage /app/node_modules ./node_modules
COPY --from=build --chown=backstage:backstage /app/packages/backend/node_modules ./packages/backend/node_modules

# Copy app-built static files (frontend is served by backend)
COPY --from=build --chown=backstage:backstage /app/packages/app/dist ./packages/app/dist

# Copy configuration files (they can be overridden via mounted volumes)
COPY --chown=backstage:backstage app-config.yaml app-config.production.yaml ./

# Copy example data for catalog
COPY --chown=backstage:backstage examples ./examples

# Switch to non-root user
USER backstage

# Expose backend port
EXPOSE 7007

# Add healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://localhost:7007/healthcheck', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# Start backend (it will also serve frontend static files)
CMD ["node", "packages/backend", "--config", "app-config.yaml", "--config", "app-config.production.yaml"]
