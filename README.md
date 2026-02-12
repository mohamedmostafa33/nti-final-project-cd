# Reddit Clone — CD Repository

<p align="center">
  <img src="docs/arch.jpeg" alt="Platform Architecture" width="100%"/>
</p>

GitOps continuous delivery repository for the Reddit Clone platform. Contains Helm charts, ArgoCD application manifests, platform lifecycle scripts, Kubernetes reference manifests, monitoring configuration, ELK logging stack, and n8n notification workflows. ArgoCD watches this repository and automatically syncs all changes to the EKS cluster.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Repository Structure](#repository-structure)
- [Platform Components](#platform-components)
- [Helm Charts](#helm-charts)
  - [Gateway Chart](#gateway-chart)
  - [Backend Chart](#backend-chart)
  - [Frontend Chart](#frontend-chart)
  - [Monitoring Chart](#monitoring-chart)
  - [Elasticsearch Chart](#elasticsearch-chart)
  - [Kibana Chart](#kibana-chart)
  - [Filebeat Chart](#filebeat-chart)
- [ArgoCD Configuration](#argocd-configuration)
  - [App-of-Apps Pattern](#app-of-apps-pattern)
  - [Sync Waves](#sync-waves)
  - [Sync Policy](#sync-policy)
- [Platform Lifecycle](#platform-lifecycle)
  - [Bootstrap](#bootstrap)
  - [Teardown](#teardown)
- [CI/CD Integration Flow](#cicd-integration-flow)
- [Networking and Routing](#networking-and-routing)
- [TLS and Certificates](#tls-and-certificates)
- [Monitoring and Observability](#monitoring-and-observability)
- [Logging (ELK Stack)](#logging-elk-stack)
- [Notifications (n8n)](#notifications-n8n)
- [Kubernetes Reference Manifests](#kubernetes-reference-manifests)
- [Required Secrets](#required-secrets)
- [Manual Helm Commands](#manual-helm-commands)
- [Related Repositories](#related-repositories)

---

## Architecture Overview

| Property | Value |
|---|---|
| **Cluster** | AWS EKS (provisioned by Terraform in the infra repo) |
| **GitOps Engine** | ArgoCD (App-of-Apps pattern) |
| **Ingress** | NGINX Gateway Fabric (Kubernetes Gateway API) |
| **TLS** | cert-manager + Let's Encrypt (HTTP-01 via Gateway API) |
| **Monitoring** | kube-prometheus-stack (Prometheus + Grafana + Alertmanager) |
| **Logging** | ELK stack (Elasticsearch 8.5.1 + Kibana 8.5.1 + Filebeat 8.5.1) |
| **Notifications** | n8n workflow (Slack + Telegram) |
| **Domain** | `www.abdallahfekry.com` |
| **Container Registry** | AWS ECR |

---

## Repository Structure

```
nti-final-project-cd/
├── README.md                              # This file
├── TROUBLESHOOTING.md                     # Operational troubleshooting guide
├── docs/
│   └── arch.jpeg                          # Platform architecture diagram
├── argocd/                                # ArgoCD configuration
│   ├── README.md                          # ArgoCD setup documentation
│   ├── root-app.yaml                      # Root Application (App-of-Apps)
│   ├── install/
│   │   ├── bootstrap.sh                   # Full platform bootstrap script
│   │   ├── teardown.sh                    # Full platform teardown script
│   │   ├── argocd-config.yaml             # ArgoCD ConfigMap and RBAC
│   │   └── .env                           # Secrets file (gitignored)
│   └── apps/
│       ├── gateway.yaml                   # sync-wave 0 — Gateway + TLS
│       ├── backend.yaml                   # sync-wave 1 — Django API
│       ├── frontend.yaml                  # sync-wave 2 — Next.js
│       ├── monitoring.yaml                # sync-wave 3 — Prometheus + Grafana
│       ├── elasticsearch.yaml             # sync-wave 3 — Elasticsearch
│       ├── kibana.yaml                    # sync-wave 4 — Kibana
│       └── filebeat.yaml                  # sync-wave 4 — Filebeat
├── helm-charts/                           # Helm charts (managed by ArgoCD)
│   ├── backend/                           # Django REST API
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
│   │       ├── migrate-job.yaml           # Helm post-install hook
│   │       └── superuser-job.yaml         # Helm post-install hook
│   ├── frontend/                          # Next.js application
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── _helpers.tpl
│   │       ├── configmap.yaml
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       └── httproute.yaml
│   ├── gateway/                           # NGINX Gateway + TLS
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── _helpers.tpl
│   │       ├── certificates.yaml          # cert-manager Certificate
│   │       ├── gateway.yaml               # Gateway API resource
│   │       ├── httproute.yaml             # Combined route (disabled)
│   │       └── redirect-route.yaml        # HTTP to HTTPS redirect
│   ├── monitoring/                        # kube-prometheus-stack wrapper
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── _helpers.tpl
│   │       ├── grafana-dashboard.yaml     # Django backend dashboard
│   │       └── servicemonitor.yaml        # Backend metrics scraping
│   ├── elasticsearch/                     # Elasticsearch (subchart)
│   │   ├── Chart.yaml
│   │   └── values.yaml
│   ├── kibana/                            # Kibana (subchart)
│   │   ├── Chart.yaml
│   │   └── values.yaml
│   └── filebeat/                          # Filebeat (subchart)
│       ├── Chart.yaml
│       └── values.yaml
├── k8s/                                   # Raw Kubernetes manifests (reference)
│   ├── namespace.yml
│   ├── reference-grants.yaml
│   ├── backend/
│   │   ├── Backend-HPA.yml
│   │   ├── configmap.yaml
│   │   ├── deployment.yaml
│   │   ├── httproute.yaml
│   │   ├── secret.yml
│   │   ├── service.yaml
│   │   └── ServiceMonitor.yml
│   ├── frontend/
│   │   ├── deployment.yaml
│   │   ├── Frontend-HPA.yml
│   │   ├── httproute.yaml
│   │   └── service.yaml
│   ├── gateway/
│   │   ├── certificate.yaml
│   │   ├── gateway.yaml
│   │   └── redirect-httproute.yaml
│   ├── network-policies/
│   │   ├── backend-allow-gateway.yaml
│   │   ├── backend-default-deny.yaml
│   │   ├── frontend-allow-gateway.yaml
│   │   └── frontend-default-deny.yaml
│   └── external-secrets/                  # Reserved for ExternalSecrets
└── n8n/
    └── workflow.json                      # n8n notification workflow
```

---

## Platform Components

| Component | Namespace | Helm Chart | Description |
|---|---|---|---|
| NGINX Gateway Fabric | `nginx-gateway` | Installed via OCI (bootstrap) | Kubernetes Gateway API implementation |
| cert-manager | `cert-manager` | Installed via Helm (bootstrap) | Automated TLS certificate management |
| ArgoCD | `argocd` | Installed via manifests (bootstrap) | GitOps continuous delivery engine |
| Gateway + TLS | `default` | `helm-charts/gateway` | Gateway resource, Certificate, HTTP-to-HTTPS redirect |
| Backend API | `reddit-app` | `helm-charts/backend` | Django REST API deployment |
| Frontend | `reddit-app` | `helm-charts/frontend` | Next.js application deployment |
| Monitoring | `monitoring` | `helm-charts/monitoring` | Prometheus, Grafana, Alertmanager, node-exporter |
| Elasticsearch | `elk` | `helm-charts/elasticsearch` | Log storage and search engine |
| Kibana | `elk` | `helm-charts/kibana` | Log visualization UI |
| Filebeat | `elk` | `helm-charts/filebeat` | Log shipper (DaemonSet) |

---

## Helm Charts

### Gateway Chart

Manages the cluster entry point with TLS termination.

| Template | Resource | Purpose |
|---|---|---|
| `gateway.yaml` | Gateway | Kubernetes Gateway API resource with HTTP (80) and HTTPS (443) listeners |
| `certificates.yaml` | Certificate | cert-manager Certificate for `www.abdallahfekry.com` via Let's Encrypt |
| `redirect-route.yaml` | HTTPRoute | HTTP-to-HTTPS 301 redirect |
| `httproute.yaml` | HTTPRoute | Combined route (disabled — using per-app routes instead) |

**Key values:**

| Key | Value |
|---|---|
| `gateway.gatewayClassName` | `nginx` |
| `tls.issuerName` | `letsencrypt-prod` |
| `tls.certificates[0].dnsNames` | `www.abdallahfekry.com` |
| `redirectRoute.enabled` | `true` |

### Backend Chart

Deploys the Django REST API with database migration and superuser creation hooks.

| Template | Resource | Purpose |
|---|---|---|
| `namespace.yaml` | Namespace | Creates `reddit-app` namespace |
| `configmap.yaml` | ConfigMap | Django environment variables (non-sensitive) |
| `secret.yaml` | Secret | Sensitive credentials (disabled — injected via bootstrap) |
| `deployment.yaml` | Deployment | Django application pods with health probes |
| `service.yaml` | Service | ClusterIP service on port 8000 |
| `httproute.yaml` | HTTPRoute | Routes `/api`, `/admin`, `/static`, `/media` to backend |
| `migrate-job.yaml` | Job | Helm post-install hook — runs `python manage.py migrate` |
| `superuser-job.yaml` | Job | Helm post-install hook — creates Django superuser |

**Key values:**

| Key | Value |
|---|---|
| `deployment.image` | `{ECR_URL}/reddit-backend:{SHA}` (updated by CI) |
| `deployment.replicas` | `1` |
| `deployment.resources.requests` | 200m CPU / 256Mi memory |
| `deployment.resources.limits` | 500m CPU / 512Mi memory |
| `configmap.data.USE_S3` | `true` |
| `configmap.data.DJANGO_DEBUG` | `False` |
| `secret.create` | `false` (secret injected via bootstrap script) |

**Health probes:**

| Probe | Path | Port | Initial Delay |
|---|---|---|---|
| Liveness | `/health/liveness/` | 8000 | 30s |
| Readiness | `/health/readiness/` | 8000 | 10s |

Both probes inject `Host: localhost` header to satisfy Django `ALLOWED_HOSTS` validation.

### Frontend Chart

Deploys the Next.js application.

| Template | Resource | Purpose |
|---|---|---|
| `configmap.yaml` | ConfigMap | `NEXT_PUBLIC_API_URL` environment variable |
| `deployment.yaml` | Deployment | Next.js application pods with health probes |
| `service.yaml` | Service | ClusterIP service on port 80 (targets 3000) |
| `httproute.yaml` | HTTPRoute | Routes `/` (catch-all) to frontend |

**Key values:**

| Key | Value |
|---|---|
| `deployment.image` | `{ECR_URL}/reddit-frontend:{SHA}` (updated by CI) |
| `deployment.replicas` | `1` |
| `deployment.resources.requests` | 100m CPU / 128Mi memory |
| `deployment.resources.limits` | 200m CPU / 256Mi memory |
| `configmap.data.NEXT_PUBLIC_API_URL` | `https://www.abdallahfekry.com/api` |
| `service.port` | `80` |
| `service.targetPort` | `3000` |

### Monitoring Chart

Wraps `kube-prometheus-stack` (v81.5.2) with project-specific configuration.

| Component | Configuration |
|---|---|
| Grafana | Enabled, LoadBalancer service, default dashboards, no persistence |
| Prometheus | 10-day retention, 10Gi PVC, auto-discover all ServiceMonitors |
| Alertmanager | Enabled |
| Node Exporter | Enabled |
| Kube State Metrics | Enabled |

**Custom templates:**

- `servicemonitor.yaml` — Scrapes Django backend `/metrics` endpoint every 15 seconds
- `grafana-dashboard.yaml` — Pre-configured Django dashboard with 10 panels:
  - Total HTTP Requests, Total DB Queries, 5xx Errors, Avg Request Latency
  - Request Rate by Method, Response Rate by Status Code
  - Request Latency by View (p50/p95/p99), DB Query Duration
  - DB Connections, Response Body Size

### Elasticsearch Chart

Wraps the official Elastic Helm chart (v8.5.1) as a subchart dependency.

| Setting | Value |
|---|---|
| Replicas | 1 |
| Java Heap | `-Xmx1g -Xms1g` |
| Storage | 5Gi PVC |
| Resources | 250m-1 CPU / 1Gi-2Gi memory |

### Kibana Chart

Wraps the official Elastic Helm chart (v8.5.1).

| Setting | Value |
|---|---|
| Elasticsearch Host | `https://elasticsearch-master:9200` |
| Service Type | ClusterIP |
| Resources | 250m-500m CPU / 512Mi-1Gi memory |

### Filebeat Chart

Wraps the official Elastic Helm chart (v8.5.1). Runs as a DaemonSet.

| Setting | Value |
|---|---|
| Input Type | Container logs (`/var/log/containers/*.log`) |
| Output | Elasticsearch (`https://elasticsearch-master:9200`) |
| Processors | `add_kubernetes_metadata` |
| Resources | 100m-250m CPU / 128Mi-256Mi memory |

---

## ArgoCD Configuration

### App-of-Apps Pattern

A single root application (`reddit-clone-apps`) points to the `argocd/apps/` directory. ArgoCD reads all YAML files in that directory and creates/manages child applications automatically.

**Root application:** `argocd/root-app.yaml`

| Property | Value |
|---|---|
| Name | `reddit-clone-apps` |
| Namespace | `argocd` |
| Source Path | `argocd/apps` |
| Target Revision | `main` |
| Destination | `https://kubernetes.default.svc` |

### Sync Waves

Applications are deployed in order using ArgoCD sync wave annotations:

| Wave | Application | Namespace | Reason |
|---|---|---|---|
| 0 | Gateway | `default` | Must be ready before routes are attached |
| 1 | Backend | `reddit-app` | Depends on Gateway for routing |
| 2 | Frontend | `reddit-app` | Depends on Backend API and Gateway |
| 3 | Monitoring | `monitoring` | Observability stack (independent) |
| 3 | Elasticsearch | `elk` | Log storage (independent) |
| 4 | Kibana | `elk` | Depends on Elasticsearch |
| 4 | Filebeat | `elk` | Depends on Elasticsearch |

### Sync Policy

All applications share the same automated sync policy:

| Property | Value |
|---|---|
| Automated | Yes |
| Prune | Yes — removes resources deleted from Git |
| Self-Heal | Yes — reverts manual cluster changes |
| Create Namespace | Yes — auto-creates target namespaces |
| Retry | Up to 5 retries with exponential backoff (5s base, 3m max) |

The monitoring application additionally uses `ServerSideApply=true` to handle large CRDs.

---

## Platform Lifecycle

### Bootstrap

The `argocd/install/bootstrap.sh` script sets up the entire platform on a bare EKS cluster:

| Step | Action |
|---|---|
| 1 | Install Gateway API CRDs (v1.2.1) |
| 2 | Install NGINX Gateway Fabric (OCI Helm chart) |
| 3 | Install cert-manager (v1.17.1) with Gateway API support + create Let's Encrypt ClusterIssuer |
| 4 | Create `reddit-app` namespace + inject `reddit-app-secret` |
| 5 | Install ArgoCD from official manifests + apply custom ConfigMap and RBAC |
| 6 | Deploy root application (App-of-Apps) |
| 7 | Wait for Gateway to be created and programmed |
| 8 | Wait for TLS certificates to be issued |

**Usage:**

```bash
# Create .env file with required secrets first
chmod +x argocd/install/bootstrap.sh
./argocd/install/bootstrap.sh
```

**Required secrets in `.env`:**

```dotenv
DJANGO_SECRET_KEY=<django-secret>
AWS_ACCESS_KEY_ID=<aws-key>
AWS_SECRET_ACCESS_KEY=<aws-secret>
DATABASE_URL=postgresql://user:pass@rds-endpoint:5432/dbname
```

### Teardown

The `argocd/install/teardown.sh` script removes all platform components. Run before `terraform destroy`.

| Step | Action |
|---|---|
| 1 | Remove ArgoCD applications (strip finalizers first) |
| 2 | Delete app workloads and secrets from `reddit-app` |
| 3 | Delete monitoring stack (PVCs, resources, namespace) |
| 4 | Delete ELK stack (PVCs, resources, namespace) |
| 5 | Delete Gateway resources and TLS certificates |
| 6 | Uninstall NGINX Gateway Fabric |
| 7 | Uninstall cert-manager and CRDs |
| 8 | Uninstall ArgoCD and CRDs |
| 9 | Remove Gateway API CRDs |
| 10 | Delete `reddit-app` namespace |
| 11 | Verify clean state (no LoadBalancers, no stuck namespaces) |

The script handles stuck namespaces by force-removing finalizers after a timeout.

**Usage:**

```bash
chmod +x argocd/install/teardown.sh
./argocd/install/teardown.sh
# Then: cd nti-final-project-infra/infra && terraform destroy
```

---

## CI/CD Integration Flow

```
Developer Push ─── CI Pipeline (GitHub Actions) ─── ECR Push
                                                        │
                                                        ▼
                                               Update values.yaml
                                               (deployment.image)
                                                        │
                                                        ▼
                                                CD Repo (this repo)
                                                        │
                                                        ▼
                                                ArgoCD detects change
                                                        │
                                                        ▼
                                                Sync to EKS cluster
```

1. CI pipeline in the CI repository builds and pushes Docker images to ECR
2. CI pipeline clones this repository and uses `yq` to update `deployment.image` in the corresponding `helm-charts/{app}/values.yaml`
3. CI pipeline commits with message `chore(backend|frontend): update image tag to {SHA}` and pushes to `main`
4. ArgoCD detects the commit and automatically syncs the affected application
5. Kubernetes pulls the new image from ECR and performs a rolling update

---

## Networking and Routing

### Gateway API Architecture

Traffic flows through the NGINX Gateway Fabric using Kubernetes Gateway API resources:

```
Internet
  │
  ▼
NGINX Gateway Fabric (LoadBalancer)
  │
  ├── HTTP (80) ──▶ HTTPRoute: redirect to HTTPS (301)
  │
  └── HTTPS (443) ──▶ TLS Termination
                        │
                        ├── /api/*      ──▶ reddit-backend-service:8000
                        ├── /admin/*    ──▶ reddit-backend-service:8000
                        ├── /static/*   ──▶ reddit-backend-service:8000
                        ├── /media/*    ──▶ reddit-backend-service:8000
                        └── /*          ──▶ reddit-frontend-service:80
```

HTTPRoutes are deployed in the `reddit-app` namespace (same as the services), referencing the Gateway in the `default` namespace via `parentRefs`.

### Services

| Service | Namespace | Type | Port | Target |
|---|---|---|---|---|
| `reddit-backend-service` | `reddit-app` | ClusterIP | 8000 | 8000 |
| `reddit-frontend-service` | `reddit-app` | ClusterIP | 80 | 3000 |

---

## TLS and Certificates

| Property | Value |
|---|---|
| Issuer | Let's Encrypt (production) |
| Challenge Type | HTTP-01 via Gateway API |
| Certificate Name | `reddit-tls-cert` |
| Domain | `www.abdallahfekry.com` |
| Namespace | `default` |

cert-manager automatically:
1. Creates an ACME order
2. Provisions an HTTP-01 challenge solver via `gatewayHTTPRoute`
3. Validates domain ownership
4. Stores the issued certificate as a Kubernetes Secret
5. The Gateway references this Secret for TLS termination

---

## Monitoring and Observability

### Stack Components

| Component | Purpose |
|---|---|
| Prometheus | Metrics collection (10-day retention, 10Gi storage) |
| Grafana | Dashboards and visualization (LoadBalancer access) |
| Alertmanager | Alert routing and notification |
| Node Exporter | Host-level metrics |
| Kube State Metrics | Kubernetes object metrics |

### Django Backend Monitoring

- **ServiceMonitor**: Scrapes `/metrics` on the `reddit-backend-service` every 15 seconds
- **Grafana Dashboard**: Pre-configured "Reddit Clone - Django Backend" dashboard with panels for:
  - HTTP request rate, response status codes, and 5xx errors
  - Request latency percentiles (p50, p95, p99) by view
  - Database query duration and connection rates
  - Response body size throughput

### Access Grafana

```bash
kubectl get svc -n monitoring | grep grafana
```

Default credentials: `admin` / `admin`

---

## Logging (ELK Stack)

| Component | Role | Namespace |
|---|---|---|
| Elasticsearch | Log storage and indexing (1 replica, 5Gi PVC) | `elk` |
| Kibana | Log visualization UI | `elk` |
| Filebeat | DaemonSet log collector from container logs | `elk` |

Filebeat collects all container logs from `/var/log/containers/*.log`, enriches them with Kubernetes metadata, and ships to Elasticsearch.

---

## Notifications (n8n)

The `n8n/workflow.json` file contains an n8n workflow that receives webhook notifications from the CI pipeline:

**Flow:**

```
Webhook (POST) ─── If status exists ─┬── Success ─── Slack + Telegram
                                      └── Failure ─── Slack + Telegram
```

| Channel | Integration |
|---|---|
| Slack | Webhook HTTP POST |
| Telegram | Telegram Bot API |

The payload includes repository name, actor, environment, commit SHA, and run ID.

---

## Kubernetes Reference Manifests

The `k8s/` directory contains raw Kubernetes manifests used during initial development before migrating to Helm charts. These serve as reference and include resources not yet in Helm:

| Resource | Description |
|---|---|
| `namespace.yml` | Original multi-namespace layout (reddit-front, reddit-back, reddit-gateway) |
| `reference-grants.yaml` | ReferenceGrant for cross-namespace Gateway API routing |
| `backend/Backend-HPA.yml` | HorizontalPodAutoscaler (1-5 replicas, 90% CPU target) |
| `frontend/Frontend-HPA.yml` | HorizontalPodAutoscaler (1-5 replicas, 90% CPU target) |
| `backend/ServiceMonitor.yml` | Prometheus ServiceMonitor for backend metrics |
| `network-policies/*.yaml` | Default-deny ingress + allow-gateway policies |

---

## Required Secrets

### Bootstrap `.env` File

| Variable | Description |
|---|---|
| `DJANGO_SECRET_KEY` | Django application secret key |
| `AWS_ACCESS_KEY_ID` | AWS credentials for S3 storage |
| `AWS_SECRET_ACCESS_KEY` | AWS credentials for S3 storage |
| `DATABASE_URL` | PostgreSQL connection string (RDS endpoint) |

### CI Repository Secrets (for image tag updates)

| Secret | Purpose |
|---|---|
| `CD_REPO_TOKEN` | GitHub PAT with write access to this repository |
| `CD_REPO_URL` | This repository path (e.g., `org/nti-final-project-cd`) |

---

## Manual Helm Commands

### Lint Charts

```bash
helm lint helm-charts/backend
helm lint helm-charts/frontend
helm lint helm-charts/gateway
helm lint helm-charts/monitoring
```

### Template Charts (dry-run)

```bash
helm template reddit-backend helm-charts/backend -n reddit-app
helm template reddit-frontend helm-charts/frontend -n reddit-app
helm template reddit-gateway helm-charts/gateway -n default
helm template monitoring helm-charts/monitoring -n monitoring
```

### Install Charts Manually

```bash
# 1. Gateway (must be first)
helm upgrade --install reddit-gateway helm-charts/gateway -n default

# 2. Backend
helm upgrade --install reddit-backend helm-charts/backend -n reddit-app --create-namespace

# 3. Frontend
helm upgrade --install reddit-frontend helm-charts/frontend -n reddit-app

# 4. Monitoring
helm upgrade --install monitoring helm-charts/monitoring -n monitoring --create-namespace

# 5. ELK Stack
helm upgrade --install elasticsearch helm-charts/elasticsearch -n elk --create-namespace
helm upgrade --install kibana helm-charts/kibana -n elk
helm upgrade --install filebeat helm-charts/filebeat -n elk
```

### Access ArgoCD UI

```bash
# Get LoadBalancer URL
kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

---

## Related Repositories

| Repository | Purpose |
|---|---|
| **nti-final-project-ci** | Application source code and CI pipelines (GitHub Actions) |
| **nti-final-project-infra** | Terraform infrastructure (VPC, EKS, RDS, S3, ECR) |