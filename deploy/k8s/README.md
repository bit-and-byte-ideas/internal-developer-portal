# Kubernetes Deployment for Backstage

This directory contains Kubernetes manifests for deploying Backstage using Kustomize.

## Structure

```text
deploy/
├── kind/
│   └── kind-config.yaml       # kind cluster config for local testing
└── k8s/
    ├── base/                      # Base Kubernetes resources (reusable)
    │   ├── deployment.yaml        # Backstage deployment with health probes
    │   ├── service.yaml          # ClusterIP service
    │   ├── ingress.yaml          # Ingress (optional, disabled in local)
    │   └── kustomization.yaml    # Base kustomization
    └── overlays/
        ├── docker-desktop/       # Local Docker Desktop configuration
        │   └── kustomization.yaml
        └── local/                # Local kind + CloudNativePG Postgres
            ├── kustomization.yaml
            ├── namespace.yaml
            ├── postgres-cluster.yaml      # CNPG Cluster CR
            └── dev/
                ├── secret-github-credentials.yaml.example  # committed template
                └── secret-github-credentials.yaml          # gitignored, real values
```

Two ways to run this locally:

- **`local`** — a disposable [`kind`](https://kind.sigs.k8s.io) cluster with a real Postgres via [CloudNativePG](https://cloudnative-pg.io). Fully scripted via the root `Makefile`. This is the recommended path — see below.
- **`docker-desktop`** — Docker Desktop's built-in Kubernetes. Manual `kubectl`/`kustomize` steps only (no Postgres wired up).

## Local kind + CloudNativePG (recommended)

### Prerequisites

1. **Docker** — the devcontainer's docker-in-docker daemon works fine for this
2. **kubectl** and **helm** — already present in the devcontainer
3. **kind** — installed automatically by `make tools` if missing (also declared as a devcontainer feature; rebuild the devcontainer to get it pre-installed instead)

### One-time secret setup

```bash
cp deploy/k8s/overlays/local/dev/secret-github-credentials.yaml.example \
   deploy/k8s/overlays/local/dev/secret-github-credentials.yaml
# then fill in real values — this file is gitignored, never commit it
```

Postgres, catalog sync, and backend health all work even with the OAuth fields left as placeholders — only interactive "Sign in with GitHub" needs them filled in. `make deploy` warns (doesn't block) if they're still unfilled.

### Deploy

```bash
make local-up
```

This runs the full pipeline from a cold state: installs `kind` if needed, creates the cluster, installs the CloudNativePG operator via Helm, builds the Backstage image, loads it into the cluster, applies the manifests, and waits for both the Postgres cluster and the Backstage rollout to be ready. Takes a few minutes on first run (subsequent runs skip cluster/operator setup if they already exist).

```bash
make port-forward   # in a separate terminal
```

Then open <http://localhost:7007>.

### Day-to-day

```bash
make reload   # rebuild the image, reload it into kind, restart the rollout
make status   # pods, services, and the Postgres Cluster at a glance
make logs     # tail the Backstage backend logs
```

Run `make help` for the full target list. `make local-down` tears down the kind cluster entirely — this destroys the Postgres volume and all data with it.

### Notes

- The CNPG operator is installed once, cluster-wide, via Helm (`make cnpg-install`) — it isn't part of the Kustomize overlay, since Kustomize can't guarantee the `Cluster` CRD is registered before applying a `Cluster` resource that depends on it.
- Backstage's `POSTGRES_HOST/PORT/USER/PASSWORD` env vars are wired to the keys CloudNativePG puts in its auto-generated `backstage-db-app` secret (`host`/`port`/`user`/`password`).
- First sign-in right after a fresh deploy may fail until the catalog's GitHub org sync completes (`initialDelay: 1 minute` in `app-config.yaml`) — the sign-in resolver needs your `User` entity to already be ingested.

## Docker Desktop (manual, no Postgres)

### Prerequisites

1. **Docker** - Build the Backstage image
2. **kubectl** - Kubernetes CLI
3. **Docker Desktop** with Kubernetes enabled

## Build Docker Image

```bash
# From repository root
docker build -t backstage:local .
```

The build process:

- Uses Node 20 LTS
- Multi-stage build (build + runtime)
- Runs as non-root user (backstage:backstage)
- Includes healthcheck on /healthcheck endpoint
- Backend serves frontend static assets

## Deploy to Docker Desktop Kubernetes

### 1. Create namespace

```bash
kubectl create namespace backstage
```

### 2. Apply manifests using Kustomize

```bash
# From repository root
kubectl apply -k deploy/k8s/overlays/docker-desktop
```

### 3. Verify deployment

```bash
# Check pod status
kubectl get pods -n backstage

# Check logs
kubectl logs -n backstage -l app=backstage -f
```

### 4. Access Backstage

Since ingress is disabled for docker-desktop, use port-forward:

```bash
kubectl port-forward -n backstage svc/backstage 7007:7007
```

Then open <http://localhost:7007> in your browser.

## Configuration

The image bakes in `app-config.yaml` + `app-config.production.yaml` (see the Dockerfile's `CMD`) — there's no separate `app-config.k8s.yaml`. `app-config.production.yaml` expects a Postgres connection via `POSTGRES_HOST/PORT/USER/PASSWORD` env vars, which this overlay doesn't currently provide — see the `local` overlay above for a working example of wiring those up via CloudNativePG. Without them, the backend will fail to connect to a database on startup.

To customize configuration, edit `app-config.production.yaml` (or add an overlay-specific one and mount it), rebuild the image, and:

1. `kubectl apply -k deploy/k8s/overlays/docker-desktop`
2. `kubectl rollout restart deployment/backstage -n backstage`

## Environment Variables

To add environment variables, edit `deploy/k8s/base/deployment.yaml` and add them to the `env:` section:

```yaml
env:
  - name: MY_VAR
    value: 'my-value'
  - name: MY_SECRET
    valueFrom:
      secretKeyRef:
        name: my-secret
        key: my-key
```

## Health Checks

- **Readiness probe**: `/healthcheck` - Ensures pod is ready to receive traffic
- **Liveness probe**: `/healthcheck` - Restarts pod if unhealthy

## Resource Limits

Default limits (adjust in `deployment.yaml` if needed):

- Memory: 512Mi request, 1Gi limit
- CPU: 250m request, 1000m limit

## Cleanup

```bash
# Delete all resources
kubectl delete -k deploy/k8s/overlays/docker-desktop

# Delete namespace
kubectl delete namespace backstage
```

## Production Deployment

For production deployments to real clusters:

1. Create a new overlay in `deploy/k8s/overlays/production/`
2. Configure appropriate:
   - Replicas (e.g., 3 for HA)
   - Resource limits
   - Ingress with TLS
   - PostgreSQL database connection
   - Secrets management
   - Persistent volumes if needed
3. Use production-grade app-config with proper auth providers

## Troubleshooting

### Pod not starting

```bash
kubectl describe pod -n backstage -l app=backstage
kubectl logs -n backstage -l app=backstage
```

### Image pull issues

Ensure the image `backstage:local` exists:

```bash
docker images | grep backstage
```

### Port already in use

If port 7007 is already in use, change the local port:

```bash
kubectl port-forward -n backstage svc/backstage 8080:7007
```

Then access at <http://localhost:8080>
