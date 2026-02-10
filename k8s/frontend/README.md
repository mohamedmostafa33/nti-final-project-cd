# Frontend - Raw Manifests (Legacy)

Raw Kubernetes manifests for the frontend service. These are kept as reference; production deployments use the Helm chart at `helm-charts/frontend/`.

## Files

| File | Description |
|------|-------------|
| deployment.yaml | Frontend Deployment (2 replicas, port 3000) |
| service.yaml | ClusterIP Service (port 80 -> 3000) |

## Note

For production use, deploy via ArgoCD using the Helm chart. See the repository root README for details.
