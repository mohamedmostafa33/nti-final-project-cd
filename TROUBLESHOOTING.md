# Troubleshooting Guide

Solutions to issues encountered during platform setup and operation.

---

## Table of Contents

1. [Terraform Dual AWS Credentials](#1-terraform-dual-aws-credentials)
2. [cert-manager Gateway API Support](#2-cert-manager-gateway-api-support)
3. [ACME Challenges Failing for Apex Domain](#3-acme-challenges-failing-for-apex-domain)
4. [Backend CrashLoopBackOff](#4-backend-crashloopbackoff)
5. [Gateway HTTPS Listener Invalid](#5-gateway-https-listener-invalid)
6. [Backend Health Probes Returning 400](#6-backend-health-probes-returning-400)
7. [ArgoCD Sync Failures](#7-argocd-sync-failures)
8. [Stuck Namespaces on Deletion](#8-stuck-namespaces-on-deletion)
9. [Monitoring CRD Conflicts](#9-monitoring-crd-conflicts)
10. [ELK Stack Not Receiving Logs](#10-elk-stack-not-receiving-logs)

---

## 1. Terraform Dual AWS Credentials

**Problem:** Terraform state lives in one AWS account while infrastructure deploys to another.

**Symptom:** `terraform plan` fails with authentication errors, or state operations target the wrong account.

**Solution:** Use environment variables for the S3 backend (state account) and `provider.tf` variables for the target account. In GitHub Actions, set `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` for state and `TF_VAR_target_aws_*` for the target.

| Secret | Purpose |
|---|---|
| `STATE_AWS_ACCESS_KEY_ID` | S3 state bucket access |
| `STATE_AWS_SECRET_ACCESS_KEY` | S3 state bucket access |
| `TARGET_AWS_ACCESS_KEY_ID` | Infrastructure deployment |
| `TARGET_AWS_SECRET_ACCESS_KEY` | Infrastructure deployment |

---

## 2. cert-manager Gateway API Support

**Problem:** ACME HTTP-01 challenges fail because cert-manager does not enable Gateway API support by default.

**Symptom:** `gateway api is not enabled, please pass the --enable-gateway-api flag`

**Solution:** Install cert-manager with the Gateway API flag enabled:

```bash
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version v1.17.1 \
  --set crds.enabled=true \
  --set config.enableGatewayAPI=true
```

This is already handled in the `bootstrap.sh` script.

---

## 3. ACME Challenges Failing for Apex Domain

**Problem:** Let's Encrypt issues a certificate for `www.abdallahfekry.com` but not the apex domain `abdallahfekry.com`.

**Root Cause:** The apex domain A records in GoDaddy point to incorrect IPs (not the EKS LoadBalancer). Only the `www` CNAME record is correct.

**Solution Applied:** Use `www` subdomain only for both the Certificate and Gateway listener. The Gateway chart's `tls.certificates[0].dnsNames` only lists `www.abdallahfekry.com`.

**To fix apex domain:** Update DNS in GoDaddy to either:
- Set A record to the ELB IP address (requires static IP)
- Use CNAME/Alias (if DNS provider supports ANAME/ALIAS)
- Configure URL forwarding from `abdallahfekry.com` to `https://www.abdallahfekry.com`

---

## 4. Backend CrashLoopBackOff

**Problem:** Backend pods fail with `django.db.utils.OperationalError: could not connect to server`.

**Root Cause:** `DATABASE_URL` in the `reddit-app-secret` Kubernetes Secret points to a stale or incorrect RDS endpoint.

**Diagnosis:**

```bash
kubectl logs deployment/reddit-backend -n reddit-app --tail=50
kubectl describe pod -n reddit-app -l app=reddit-backend
```

**Solution:**

```bash
# Verify the correct RDS endpoint
aws rds describe-db-instances \
  --query 'DBInstances[*].[DBInstanceIdentifier,Endpoint.Address]' \
  --output table

# Recreate the secret with the correct DATABASE_URL
kubectl delete secret reddit-app-secret -n reddit-app
kubectl create secret generic reddit-app-secret \
  --from-literal=DJANGO_SECRET_KEY="<key>" \
  --from-literal=AWS_ACCESS_KEY_ID="<key>" \
  --from-literal=AWS_SECRET_ACCESS_KEY="<secret>" \
  --from-literal=DATABASE_URL="postgresql://user:pass@correct-rds-endpoint:5432/dbname" \
  -n reddit-app

# Restart backend pods
kubectl rollout restart deployment reddit-backend -n reddit-app
```

---

## 5. Gateway HTTPS Listener Invalid

**Problem:** Gateway shows `InvalidCertificateRef` on the HTTPS listener.

**Root Cause:** cert-manager has not yet finished issuing the TLS certificate, so the referenced Secret does not exist.

**Diagnosis:**

```bash
kubectl get certificates -n default
kubectl describe certificate reddit-tls-cert -n default
kubectl get challenges --all-namespaces
```

**Solution:** Wait for cert-manager to complete the ACME challenge. The Gateway will become ready automatically once the Secret is created. This typically takes 1-3 minutes.

If the challenge is stuck:

```bash
# Check challenge status
kubectl describe challenge -n default

# Verify the ClusterIssuer is configured
kubectl get clusterissuer letsencrypt-prod -o yaml

# Verify Gateway is accepting HTTP traffic (needed for HTTP-01 challenges)
kubectl get gateway reddit-gateway -n default -o yaml
```

---

## 6. Backend Health Probes Returning 400

**Problem:** Kubelet health probes fail with HTTP 400 because the Pod IP is not in Django `ALLOWED_HOSTS`.

**Symptom:** Backend pods are marked as unhealthy and keep restarting.

**Root Cause:** Kubelet sends health check requests with the Pod IP as the `Host` header. Django rejects requests where the `Host` header does not match `ALLOWED_HOSTS`.

**Solution Applied:**

1. Added `localhost` and `127.0.0.1` to `DJANGO_ALLOWED_HOSTS` in `helm-charts/backend/values.yaml`
2. Set `Host: localhost` header on both liveness and readiness probes in the Deployment template

```yaml
livenessProbe:
  httpGet:
    path: /health/liveness/
    port: 8000
    httpHeaders:
      - name: Host
        value: localhost
```

Additionally, `*` is included in `DJANGO_ALLOWED_HOSTS` to support internal Prometheus scraping via Pod IP.

---

## 7. ArgoCD Sync Failures

**Problem:** Application stuck in `Progressing` or `Degraded` state.

**Diagnosis:**

```bash
# Check application status
kubectl describe application <app-name> -n argocd | grep -A10 "Message:"

# Check for stuck ReplicaSets
kubectl get rs -n reddit-app

# Check pod events
kubectl get events -n reddit-app --sort-by='.lastTimestamp' | tail -20
```

**Resolution Steps:**

1. Delete old stuck ReplicaSets with `0 READY` but `DESIRED > 0`:
   ```bash
   kubectl delete rs <stuck-rs-name> -n reddit-app
   ```

2. Scale deployment to 0 then back to desired count:
   ```bash
   kubectl scale deployment reddit-backend -n reddit-app --replicas=0
   kubectl scale deployment reddit-backend -n reddit-app --replicas=1
   ```

3. Force hard refresh on the ArgoCD application:
   ```bash
   kubectl patch application <app> -n argocd --type=merge \
     -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
   ```

4. Force sync with replacement:
   ```bash
   argocd app sync <app-name> --force
   ```

---

## 8. Stuck Namespaces on Deletion

**Problem:** Namespace stays in `Terminating` state indefinitely during teardown.

**Root Cause:** Finalizers on resources or the namespace itself prevent deletion.

**Solution:**

```bash
# Force-remove namespace finalizers
kubectl get namespace <ns> -o json \
  | jq '.spec.finalizers = []' \
  | kubectl replace --raw "/api/v1/namespaces/<ns>/finalize" -f -
```

The `teardown.sh` script handles this automatically via the `wait_ns_gone` helper function.

---

## 9. Monitoring CRD Conflicts

**Problem:** ArgoCD sync fails for the monitoring application with CRD-related errors.

**Root Cause:** kube-prometheus-stack includes large CRDs that exceed the default annotation size limits.

**Solution Applied:** The monitoring ArgoCD application uses `ServerSideApply=true` in its sync options:

```yaml
syncOptions:
  - ServerSideApply=true
```

Additionally, webhook configuration `caBundle` differences are ignored via `ignoreDifferences` to prevent constant drift detection.

---

## 10. ELK Stack Not Receiving Logs

**Problem:** Kibana shows no log data.

**Diagnosis:**

```bash
# Check Filebeat DaemonSet status
kubectl get daemonset -n elk

# Check Filebeat logs
kubectl logs daemonset/filebeat-filebeat -n elk --tail=50

# Check Elasticsearch health
kubectl exec -n elk elasticsearch-master-0 -- curl -sk https://localhost:9200/_cluster/health
```

**Common Causes:**

1. Filebeat cannot authenticate to Elasticsearch — verify `elasticsearch-master-credentials` Secret exists
2. Elasticsearch is not ready — check PVC is bound and pod is running
3. SSL verification fails — Filebeat config uses `ssl.verification_mode: none`

---

## Quick Diagnostic Commands

```bash
# Cluster overview
kubectl get pods -A
kubectl get applications -n argocd

# Gateway and routing
kubectl get gateway -n default
kubectl get httproute -A

# TLS certificates
kubectl get certificates -n default
kubectl describe certificate reddit-tls-cert -n default

# Application logs
kubectl logs -f deployment/reddit-backend -n reddit-app
kubectl logs -f deployment/reddit-frontend -n reddit-app

# Monitoring
kubectl get servicemonitor -A
kubectl get svc -n monitoring | grep grafana

# ELK
kubectl get pods -n elk
kubectl get pvc -n elk

# Connectivity test
curl -sI https://www.abdallahfekry.com
curl -sI https://www.abdallahfekry.com/api/communities/
```