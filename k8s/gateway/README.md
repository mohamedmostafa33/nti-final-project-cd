# Gateway - Raw Manifests (Legacy)

Raw Kubernetes manifests for the NGINX Gateway and routing. These are kept as reference; production deployments use the Helm chart at `helm-charts/gateway/`.

## Files

| File | Description |
|------|-------------|
| gateway.yaml | NGINX Gateway resource (HTTP/HTTPS listeners) |
| httproute.yaml | HTTPRoute for backend/frontend routing |

## Note

The Helm chart adds TLS certificates (cert-manager), HTTPS redirect, and parameterized hostnames. For production use, deploy via ArgoCD. See the repository root README for details.
