# ArgoCD Setup for Reddit Clone Application

This directory contains ArgoCD Application manifests for automated GitOps deployment.

## Prerequisites

1. ArgoCD installed on your Kubernetes cluster
2. ArgoCD CLI configured
3. Access to the CD repository

## Installation

### 1. Install ArgoCD (if not already installed)

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd
```

### 2. Deploy the Applications

```bash
# Apply the root application (App of Apps pattern)
kubectl apply -f argocd/root-app.yaml

# Or apply individual applications
kubectl apply -f argocd/apps/
```

### 3. Access ArgoCD UI

```bash
# Port forward to access the UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Application Structure

```
argocd/
├── root-app.yaml           # Root application (App of Apps)
├── install/
│   └── argocd-install.yaml # ArgoCD installation manifest
└── apps/
    ├── gateway.yaml        # Gateway application
    ├── backend.yaml        # Backend application
    └── frontend.yaml       # Frontend application
```

## Sync Waves

The applications are deployed in the following order using sync waves:
1. **Wave 0**: Gateway (must be deployed first)
2. **Wave 1**: Backend (depends on Gateway)
3. **Wave 2**: Frontend (depends on Backend)

## Auto-Sync

All applications are configured with auto-sync enabled:
- **Prune**: Automatically delete resources that are no longer in Git
- **SelfHeal**: Automatically sync when drift is detected
- **CreateNamespace**: Automatically create namespaces if they don't exist
