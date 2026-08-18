# Deployment Resources

This directory contains deployment resources for the Backstage application.

## Contents

- **`kind/`** - `kind` cluster config for local testing (`make local-up`, see `k8s/README.md`)
- **`k8s/`** - Kubernetes manifests with Kustomize overlays
  - `base/` - Reusable base Kubernetes resources
  - `overlays/local/` - Local `kind` + CloudNativePG Postgres (recommended)
  - `overlays/docker-desktop/` - Local Docker Desktop configuration (no Postgres wired up)

## Quick Links

- [Kubernetes Deployment Guide](./k8s/README.md)
- [General Deployment Guide](../DEPLOYMENT.md)

## Future Resources

This directory is organized to hold additional deployment resources such as:

- Terraform/IaC configurations
- Helm charts
- Cloud-specific deployment configs (AWS, GCP, Azure)
- CI/CD pipeline definitions
- Environment-specific configurations
