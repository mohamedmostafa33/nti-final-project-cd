# Backend - Raw Manifests (Legacy)

Raw Kubernetes manifests for the backend service. These are kept as reference; production deployments use the Helm chart at `helm-charts/backend/`.

## Files

| File | Description |
|------|-------------|
| deployment.yaml | Backend Deployment (2 replicas, port 8000) |
| service.yaml | ClusterIP Service |
| configmap.yaml | Environment variables |

## Note

For production use, deploy via ArgoCD using the Helm chart. See the repository root README for details.
