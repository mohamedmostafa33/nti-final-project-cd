# Reddit Clone - CD Repository

This repository contains the Kubernetes manifests and Helm charts for deploying the Reddit Clone application using GitOps with ArgoCD.

## Repository Structure

```
nti-final-project-cd/
├── README.md
├── argocd/                          # ArgoCD Configuration
│   ├── README.md
│   ├── root-app.yaml                # Root Application (App of Apps)
│   ├── install/
│   │   ├── argocd-config.yaml       # ArgoCD custom configurations
│   │   └── install-argocd.sh        # ArgoCD installation script
│   └── apps/
│       ├── gateway.yaml             # Gateway ArgoCD Application
│       ├── backend.yaml             # Backend ArgoCD Application
│       └── frontend.yaml            # Frontend ArgoCD Application
├── helm-charts/                     # Helm Charts
│   ├── backend/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── _helpers.tpl
│   │       ├── namespace.yaml
│   │       ├── configmap.yaml
│   │       ├── secret.yaml
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       ├── httproute.yaml
│   │       ├── migrate-job.yaml
│   │       └── superuser-job.yaml
│   ├── frontend/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── _helpers.tpl
│   │       ├── configmap.yaml
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       └── httproute.yaml
│   └── gateway/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── _helpers.tpl
│           ├── gateway.yaml
│           └── httproute.yaml
└── k8s/                             # Raw Kubernetes Manifests (for reference)
    ├── backend/
    ├── frontend/
    └── gateway/
```

## Quick Start

### Prerequisites

- Kubernetes cluster (EKS recommended)
- kubectl configured to connect to your cluster
- Helm 3.x installed
- ArgoCD installed (or use our installation script)

### 1. Install ArgoCD

```bash
# Using our installation script
chmod +x argocd/install/install-argocd.sh
./argocd/install/install-argocd.sh
```

### 2. Configure Repository

1. Fork/Clone this repository
2. Update the repository URL in ArgoCD applications:
   - `argocd/root-app.yaml`
   - `argocd/apps/gateway.yaml`
   - `argocd/apps/backend.yaml`
   - `argocd/apps/frontend.yaml`

3. Add the repository to ArgoCD:
```bash
argocd repo add https://github.com/YOUR_USERNAME/nti-final-project-cd.git
```

### 3. Deploy Applications

```bash
# Deploy the root application (manages all other apps)
kubectl apply -f argocd/root-app.yaml

# Or deploy individually
kubectl apply -f argocd/apps/gateway.yaml
kubectl apply -f argocd/apps/backend.yaml
kubectl apply -f argocd/apps/frontend.yaml
```

## Helm Charts

### Backend Chart

The backend chart deploys:
- Django REST API application
- ConfigMap for environment variables
- Secret for sensitive data
- Service (ClusterIP)
- HTTPRoute for API Gateway routing
- Database migration Job (post-install hook)
- Superuser creation Job (post-install hook)

**Key Values:**
```yaml
deployment:
  image: "your-ecr-url/backend-app:tag"
  replicas: 2

configmap:
  data:
    DJANGO_DEBUG: "False"
    USE_S3: "true"

secret:
  data:
    DJANGO_SECRET_KEY: "your-secret-key"
```

### Frontend Chart

The frontend chart deploys:
- Next.js application
- ConfigMap for environment variables
- Service (ClusterIP)
- HTTPRoute for frontend routing

**Key Values:**
```yaml
deployment:
  image: "your-ecr-url/reddit-frontend:tag"
  replicas: 2

configmap:
  data:
    NEXT_PUBLIC_API_URL: "http://reddit-backend-service:8000"
```

### Gateway Chart

The gateway chart deploys:
- Kubernetes Gateway API Gateway resource
- HTTPRoute for routing traffic to backend and frontend

## CI/CD Flow

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   CI Pipeline   │────▶│  Update Helm    │────▶│     ArgoCD      │
│  (Build & Push) │     │   values.yaml   │     │  (Auto Sync)    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                              │                        │
                              ▼                        ▼
                        ┌─────────────────┐     ┌─────────────────┐
                        │   CD Repo Git   │     │   Kubernetes    │
                        │     Commit      │     │     Cluster     │
                        └─────────────────┘     └─────────────────┘
```

1. **CI Pipeline** builds and pushes Docker images to ECR
2. **CI Pipeline** updates the image tag in `values.yaml`
3. **ArgoCD** detects changes and syncs automatically
4. **Kubernetes** pulls new images and deploys

## Required Secrets

### CI Repository Secrets

| Secret Name | Description |
|------------|-------------|
| `CD_REPO_TOKEN` | GitHub PAT with write access to CD repo |
| `CD_REPO_URL` | CD repository URL (e.g., `username/nti-final-project-cd`) |
| `AWS_ECR_ACCOUNT_URL` | ECR account URL |
| `AWS_ACCESS_KEY_ID` | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key |

### Kubernetes Secrets

Create the database secret:
```bash
kubectl create secret generic reddit-db-secret \
  --namespace=reddit-app \
  --from-literal=DATABASE_URL="postgresql://user:pass@host:5432/dbname"
```

## Manual Helm Commands

### Lint Charts
```bash
helm lint helm-charts/backend
helm lint helm-charts/frontend
helm lint helm-charts/gateway
```

### Template Charts (dry-run)
```bash
helm template reddit-backend helm-charts/backend -n reddit-app
helm template reddit-frontend helm-charts/frontend -n reddit-app
helm template reddit-gateway helm-charts/gateway -n default
```

### Install Charts Manually
```bash
# Install Gateway first
helm upgrade --install reddit-gateway helm-charts/gateway -n default

# Then Backend
helm upgrade --install reddit-backend helm-charts/backend -n reddit-app --create-namespace

# Finally Frontend
helm upgrade --install reddit-frontend helm-charts/frontend -n reddit-app
```

## Sync Waves

Applications are deployed in order using ArgoCD sync waves:

| Wave | Application | Description |
|------|-------------|-------------|
| 0 | Gateway | API Gateway must be ready first |
| 1 | Backend | Backend depends on Gateway |
| 2 | Frontend | Frontend depends on Backend |

## Troubleshooting

### Check ArgoCD Application Status
```bash
argocd app list
argocd app get reddit-backend
argocd app get reddit-frontend
argocd app get reddit-gateway
```

### Force Sync
```bash
argocd app sync reddit-backend --force
```

### View Helm Release
```bash
helm list -A
helm history reddit-backend -n reddit-app
```

### Check Migration Job Logs
```bash
kubectl logs -n reddit-app -l app=reddit-backend --tail=100
kubectl get jobs -n reddit-app
```

## Related Repositories

- **CI Repository**: Contains source code and CI pipelines
- **Infrastructure Repository**: Contains Terraform code for AWS infrastructure

## License

This project is part of NTI Final Project.