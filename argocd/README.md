# ArgoCD Configuration

ArgoCD Application manifests and platform lifecycle scripts for the Reddit Clone. This directory contains everything needed to bootstrap and manage the full platform on a bare EKS cluster.

---

## Table of Contents

- [Directory Structure](#directory-structure)
- [App-of-Apps Pattern](#app-of-apps-pattern)
- [Application Manifests](#application-manifests)
- [Sync Waves](#sync-waves)
- [Sync Policy](#sync-policy)
- [ArgoCD Custom Configuration](#argocd-custom-configuration)
- [Bootstrap Script](#bootstrap-script)
- [Teardown Script](#teardown-script)
- [Secrets Management](#secrets-management)
- [Accessing the ArgoCD UI](#accessing-the-argocd-ui)

---

## Directory Structure

```
argocd/
├── root-app.yaml               # Root Application (App-of-Apps)
├── install/
│   ├── bootstrap.sh            # Full platform bootstrap
│   ├── teardown.sh             # Full platform teardown
│   ├── argocd-config.yaml      # ArgoCD ConfigMap and RBAC
│   └── .env                    # Secrets file (gitignored in production)
└── apps/
    ├── gateway.yaml            # sync-wave 0 — Gateway + TLS certificates
    ├── backend.yaml            # sync-wave 1 — Django REST API
    ├── frontend.yaml           # sync-wave 2 — Next.js application
    ├── monitoring.yaml         # sync-wave 3 — kube-prometheus-stack
    ├── elasticsearch.yaml      # sync-wave 3 — Elasticsearch
    ├── kibana.yaml             # sync-wave 4 — Kibana (depends on ES)
    └── filebeat.yaml           # sync-wave 4 — Filebeat (depends on ES)
```

---

## App-of-Apps Pattern

A single root application (`reddit-clone-apps`) watches the `argocd/apps/` directory for YAML files. Each file in that directory defines a child ArgoCD Application that points to a Helm chart in `helm-charts/`.

**Root application** (`root-app.yaml`):

| Property | Value |
|---|---|
| Name | `reddit-clone-apps` |
| Source Repository | `https://github.com/mohamedmostafa33/nti-final-project-cd.git` |
| Source Path | `argocd/apps` |
| Target Revision | `main` |
| Destination Server | `https://kubernetes.default.svc` |
| Destination Namespace | `argocd` |

Adding a new application is as simple as creating a new YAML file in `argocd/apps/` and pushing to `main`. ArgoCD auto-discovers and deploys it.

---

## Application Manifests

| File | Application Name | Helm Chart Path | Target Namespace | Sync Wave |
|---|---|---|---|---|
| `gateway.yaml` | `reddit-gateway` | `helm-charts/gateway` | `default` | 0 |
| `backend.yaml` | `reddit-backend` | `helm-charts/backend` | `reddit-app` | 1 |
| `frontend.yaml` | `reddit-frontend` | `helm-charts/frontend` | `reddit-app` | 2 |
| `monitoring.yaml` | `monitoring` | `helm-charts/monitoring` | `monitoring` | 3 |
| `elasticsearch.yaml` | `elasticsearch` | `helm-charts/elasticsearch` | `elk` | 3 |
| `kibana.yaml` | `kibana` | `helm-charts/kibana` | `elk` | 4 |
| `filebeat.yaml` | `filebeat` | `helm-charts/filebeat` | `elk` | 4 |

### Ignored Differences

The `backend` and `frontend` applications ignore `/spec/replicas` on Deployments to prevent conflicts with HorizontalPodAutoscaler.

The `monitoring` application ignores `caBundle` on webhook configurations to prevent drift from cert-manager updates.

---

## Sync Waves

| Wave | Applications | Rationale |
|---|---|---|
| 0 | Gateway | Must be ready before any HTTPRoute can attach |
| 1 | Backend | Django API depends on Gateway for routing |
| 2 | Frontend | Next.js depends on Backend API and Gateway |
| 3 | Monitoring, Elasticsearch | Observability and logging infrastructure (independent) |
| 4 | Kibana, Filebeat | Depend on Elasticsearch being ready |

---

## Sync Policy

All applications use the same automated sync policy:

```yaml
syncPolicy:
  automated:
    prune: true        # Remove resources deleted from Git
    selfHeal: true     # Revert manual cluster changes
    allowEmpty: false   # Prevent accidental deletion of all resources
  syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - PruneLast=true
  retry:
    limit: 5
    backoff:
      duration: 5s
      factor: 2
      maxDuration: 3m
```

The monitoring application additionally uses `ServerSideApply=true` to handle large CRD objects, and has a longer retry backoff (10s base, 5m max).

---

## ArgoCD Custom Configuration

The `install/argocd-config.yaml` file applies two ConfigMaps after ArgoCD installation:

### argocd-cm (Settings)

| Key | Value | Purpose |
|---|---|---|
| `timeout.reconciliation` | `180s` | How often ArgoCD reconciles application state |
| `application.resourceTrackingMethod` | `annotation` | Track resources via annotations instead of labels |

### argocd-rbac-cm (RBAC)

| Role | Permissions |
|---|---|
| `readonly` (default) | Read-only access for all unauthenticated users |
| `admin` | Full access to applications, clusters, repositories, and projects |

---

## Bootstrap Script

**File:** `install/bootstrap.sh`

Sets up the complete platform on a bare EKS cluster in 8 steps:

| Step | Action | Details |
|---|---|---|
| 1 | Gateway API CRDs | Installs standard Gateway API CRDs (v1.2.1) |
| 2 | NGINX Gateway Fabric | Installs via OCI Helm chart in `nginx-gateway` namespace |
| 3 | cert-manager | Installs v1.17.1 with Gateway API support + creates Let's Encrypt ClusterIssuer |
| 4 | App namespace and secret | Creates `reddit-app` namespace + injects `reddit-app-secret` from `.env` |
| 5 | ArgoCD | Installs from official manifests + applies custom ConfigMap and RBAC |
| 6 | App-of-Apps | Applies `root-app.yaml` — ArgoCD takes over from here |
| 7 | Wait for Gateway | Waits up to 5 minutes for Gateway resource to be created and programmed |
| 8 | Wait for TLS | Waits for cert-manager to issue TLS certificate |

**Prerequisites:**

- `kubectl` configured with EKS cluster access
- Helm v3 installed
- `.env` file with required secrets (or environment variables exported)

**Usage:**

```bash
chmod +x argocd/install/bootstrap.sh
./argocd/install/bootstrap.sh                        # reads from install/.env
./argocd/install/bootstrap.sh --env-file /path/.env  # custom .env path
```

**Required secrets:**

| Variable | Description |
|---|---|
| `DJANGO_SECRET_KEY` | Django application secret key |
| `AWS_ACCESS_KEY_ID` | AWS credentials for S3 |
| `AWS_SECRET_ACCESS_KEY` | AWS credentials for S3 |
| `DATABASE_URL` | PostgreSQL connection string (RDS) |

---

## Teardown Script

**File:** `install/teardown.sh`

Removes all platform components in the correct order. Must be run before `terraform destroy` to avoid orphaned AWS resources (especially LoadBalancers).

| Step | Action |
|---|---|
| 1 | Remove ArgoCD applications (strip finalizers first) |
| 2 | Delete app workloads, secrets, and routes from `reddit-app` |
| 3 | Delete monitoring stack (PVCs, resources, namespace) |
| 4 | Delete ELK stack (PVCs, resources, namespace) |
| 5 | Delete Gateway resources and TLS certificates |
| 6 | Uninstall NGINX Gateway Fabric |
| 7 | Uninstall cert-manager and all CRDs |
| 8 | Uninstall ArgoCD and all CRDs (force-clean finalizers) |
| 9 | Remove Gateway API CRDs |
| 10 | Delete `reddit-app` namespace |
| 11 | Verify clean state |

The script handles stuck namespaces with a `wait_ns_gone` helper that force-removes finalizers after a configurable timeout.

**Usage:**

```bash
chmod +x argocd/install/teardown.sh
./argocd/install/teardown.sh
```

---

## Secrets Management

Application secrets are injected via the bootstrap script as a Kubernetes Secret (`reddit-app-secret`), not stored in Git.

The `secret.create` flag in `helm-charts/backend/values.yaml` is set to `false`, which means the Helm chart does not create the Secret — it references the one already created by the bootstrap script.

To update secrets after initial deployment:

```bash
kubectl delete secret reddit-app-secret -n reddit-app
kubectl create secret generic reddit-app-secret \
  --from-literal=DJANGO_SECRET_KEY="<key>" \
  --from-literal=AWS_ACCESS_KEY_ID="<key>" \
  --from-literal=AWS_SECRET_ACCESS_KEY="<secret>" \
  --from-literal=DATABASE_URL="postgresql://user:pass@host:5432/db" \
  -n reddit-app
kubectl rollout restart deployment reddit-backend -n reddit-app
```

---

## Accessing the ArgoCD UI

```bash
# Get the LoadBalancer URL
kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Get the admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Login with username `admin` and the retrieved password.