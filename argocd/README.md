# ArgoCD Configuration

ArgoCD Application manifests and platform lifecycle scripts for the Reddit Clone.

## Structure

```
argocd/
├── root-app.yaml           # App-of-Apps root application
├── install/
│   ├── bootstrap.sh        # Full platform bootstrap (Gateway, cert-manager, ArgoCD, apps)
│   ├── teardown.sh         # Full platform teardown (run before terraform destroy)
│   ├── argocd-config.yaml  # ArgoCD ConfigMap and RBAC
│   └── .env                # Secrets file (gitignored)
└── apps/
    ├── gateway.yaml        # sync-wave 0 -- Gateway + TLS
    ├── backend.yaml        # sync-wave 1 -- Django API
    ├── frontend.yaml       # sync-wave 2 -- Next.js
    ├── monitoring.yaml     # sync-wave 3 -- Prometheus + Grafana
    ├── elasticsearch.yaml  # sync-wave 3 -- Elasticsearch
    ├── kibana.yaml         # sync-wave 4 -- Kibana (after ES)
    └── filebeat.yaml       # sync-wave 4 -- Filebeat (after ES)
```

## Bootstrap

```bash
# Create .env with required secrets, then:
chmod +x argocd/install/bootstrap.sh
./argocd/install/bootstrap.sh
```

The script installs all prerequisites and deploys the root application. ArgoCD auto-syncs all child apps in sync-wave order.

## Teardown

```bash
chmod +x argocd/install/teardown.sh
./argocd/install/teardown.sh
```

Removes all applications, monitoring, ELK, Gateway, cert-manager, ArgoCD, and their namespaces. Run before `terraform destroy`.

## Access ArgoCD UI

```bash
# Get LoadBalancer URL
kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Sync Policy

All applications use automated sync with:
- **Prune** -- removes resources deleted from Git
- **SelfHeal** -- reverts manual cluster changes
- **CreateNamespace** -- auto-creates target namespaces
- **Retry** -- up to 5 retries with exponential backoff
