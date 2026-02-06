# ArgoCD Setup for Reddit Clone Application

This directory contains ArgoCD Application manifests for automated GitOps deployment.

## Prerequisites

1. ArgoCD installed on your Kubernetes cluster (automatically installed via Terraform from the Infrastructure Repository)
2. ArgoCD CLI configured (optional)
3. Access to the CD repository

## Installation

### ArgoCD Installation (Automated via Terraform)

**ArgoCD is now automatically installed** when you run `terraform apply` in the [Infrastructure Repository](https://github.com/mohamedmostafa33/nti-final-project-infra). The Terraform ArgoCD module will:
- Create the `argocd` namespace
- Install ArgoCD using the official Helm chart (version 7.7.16)
- Configure the ArgoCD server as a LoadBalancer service
- Set up insecure mode for easier access

### Manual Installation (Alternative)

If you need to install ArgoCD manually (for standalone setups or testing):

```bash
# Use the installation script
chmod +x argocd/install/install-argocd.sh
./argocd/install/install-argocd.sh
```

### Deploy the Applications

```bash
# Apply the root application (App of Apps pattern)
kubectl apply -f argocd/root-app.yaml

# Or apply individual applications
kubectl apply -f argocd/apps/
```

### Access ArgoCD UI

```bash
# If using LoadBalancer (default with Terraform):
kubectl get svc argocd-server -n argocd
# Access the EXTERNAL-IP in your browser

# Or port forward to access the UI locally:
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
