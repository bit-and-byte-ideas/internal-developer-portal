# Kubernetes Deployment for Backstage

This directory contains Kubernetes manifests for deploying Backstage using Kustomize.

## Structure

```
deploy/k8s/
├── base/                      # Base Kubernetes resources (reusable)
│   ├── deployment.yaml        # Backstage deployment with health probes
│   ├── service.yaml          # ClusterIP service
│   ├── ingress.yaml          # Ingress (optional, disabled in local)
│   └── kustomization.yaml    # Base kustomization
└── overlays/
    └── docker-desktop/       # Local Docker Desktop configuration
        └── kustomization.yaml # Overlay for local deployment
```

## Prerequisites

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

Then open http://localhost:7007 in your browser.

## Configuration

The deployment uses `app-config.k8s.yaml` which:
- Uses SQLite database (stored at /tmp/backstage.db)
- Enables guest authentication
- Includes example catalog entities
- Configured for local access

To customize configuration:
1. Edit `app-config.k8s.yaml` in the repository root
2. Rebuild the ConfigMap: `kubectl apply -k deploy/k8s/overlays/docker-desktop`
3. Restart pods: `kubectl rollout restart deployment/backstage -n backstage`

## Environment Variables

To add environment variables, edit `deploy/k8s/base/deployment.yaml` and add them to the `env:` section:

```yaml
env:
- name: MY_VAR
  value: "my-value"
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
Then access at http://localhost:8080
