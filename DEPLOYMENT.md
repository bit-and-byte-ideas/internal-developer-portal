# Backstage Deployment Guide

Quick reference for building and deploying Backstage locally with Docker and Kubernetes.

## Quick Start - Docker

```bash
# Build the image
docker build -t backstage:local .

# Run locally with Docker
docker run -it --rm \
  -p 7007:7007 \
  backstage:local

# Access at http://localhost:7007
```

## Quick Start - Kubernetes (Docker Desktop)

```bash
# 1. Build the Docker image
docker build -t backstage:local .

# 2. Create namespace
kubectl create namespace backstage

# 3. Deploy using Kustomize
kubectl apply -k deploy/k8s/overlays/docker-desktop

# 4. Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=backstage -n backstage --timeout=300s

# 5. Port forward to access locally
kubectl port-forward -n backstage svc/backstage 7007:7007

# 6. Open http://localhost:7007 in your browser
```

## Verify Deployment

```bash
# Check pod status
kubectl get pods -n backstage

# View logs
kubectl logs -n backstage -l app=backstage -f

# Check service
kubectl get svc -n backstage

# Describe deployment
kubectl describe deployment backstage -n backstage
```

## Update Configuration

After modifying `app-config.k8s.yaml`:

```bash
# Reapply manifests (updates ConfigMap)
kubectl apply -k deploy/k8s/overlays/docker-desktop

# Restart deployment to pick up new config
kubectl rollout restart deployment/backstage -n backstage

# Watch rollout status
kubectl rollout status deployment/backstage -n backstage
```

## Cleanup

```bash
# Delete all resources
kubectl delete -k deploy/k8s/overlays/docker-desktop

# Or delete namespace entirely
kubectl delete namespace backstage
```

## Troubleshooting

### Pod stuck in Pending

```bash
kubectl describe pod -n backstage -l app=backstage
```

Check for:

- Image pull issues
- Resource constraints
- Node selector mismatches

### Pod CrashLoopBackOff

```bash
kubectl logs -n backstage -l app=backstage --previous
```

Common issues:

- Missing configuration
- Database connection failures
- Port conflicts

### Cannot access via port-forward

Ensure pod is Ready:

```bash
kubectl get pods -n backstage
```

Check if port 7007 is already in use locally:

```bash
lsof -i :7007
```

Use alternative port:

```bash
kubectl port-forward -n backstage svc/backstage 8080:7007
```

## Configuration Files

- **`app-config.yaml`** - Development config (SQLite, GitHub OAuth)
- **`app-config.production.yaml`** - Production config (PostgreSQL)
- **`app-config.k8s.yaml`** - Kubernetes config (SQLite, guest auth, example data)

The Docker image includes all three. The default CMD uses `app-config.yaml` + `app-config.k8s.yaml`.

Override by mounting a custom config:

```yaml
volumeMounts:
  - name: custom-config
    mountPath: /app/app-config.custom.yaml
    subPath: app-config.custom.yaml
```

And updating the container args:

```yaml
args:
  - --config
  - app-config.yaml
  - --config
  - app-config.custom.yaml
```

## Advanced

### Use PostgreSQL instead of SQLite

1. Deploy PostgreSQL in the cluster
1. Create a Secret with credentials
1. Update deployment to use production config and inject secrets as env vars

```bash
kubectl create secret generic postgres-credentials \
  --from-literal=POSTGRES_HOST=postgres.backstage.svc.cluster.local \
  --from-literal=POSTGRES_PORT=5432 \
  --from-literal=POSTGRES_USER=backstage \
  --from-literal=POSTGRES_PASSWORD=your-password \
  -n backstage
```

### Enable Ingress

Edit `deploy/k8s/overlays/docker-desktop/kustomization.yaml` and remove the ingress deletion patch.

Configure ingress hostname in `deploy/k8s/base/ingress.yaml`.

Ensure you have an ingress controller installed (e.g., nginx-ingress).

### Scale Replicas

For production, increase replicas in your overlay:

```yaml
patches:
  - target:
      kind: Deployment
      name: backstage
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 3
```

## Additional Resources

- Detailed Kubernetes setup: `deploy/k8s/README.md`
- Backstage configuration: <https://backstage.io/docs/conf/>
- Docker Desktop Kubernetes: <https://docs.docker.com/desktop/kubernetes/>
