# Troubleshooting Guide

Solutions to issues encountered during project setup and operation.

## Table of Contents

1. [Terraform Dual AWS Credentials](#1-terraform-dual-aws-credentials)
2. [cert-manager Gateway API Support](#2-cert-manager-gateway-api-support)
3. [ACME Challenges Failing for Apex Domain](#3-acme-challenges-failing-for-apex-domain)
4. [Backend CrashLoopBackOff](#4-backend-crashloopbackoff)
5. [Gateway HTTPS Listener Invalid](#5-gateway-https-listener-invalid)
6. [Backend Health Probes Returning 400](#6-backend-health-probes-returning-400)
7. [ArgoCD Sync Failures](#7-argocd-sync-failures)

---

## 1. Terraform Dual AWS Credentials

**Problem:** Terraform state lives in one AWS account while infrastructure deploys to another.

**Solution:** Use environment variables for the S3 backend (state account) and `provider.tf` variables for the target account. In GitHub Actions, set `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` for state and `TF_VAR_target_aws_*` for the target.

| Secret | Purpose |
|--------|---------|
| `STATE_AWS_ACCESS_KEY_ID` | S3 state bucket |
| `STATE_AWS_SECRET_ACCESS_KEY` | S3 state bucket |
| `TARGET_AWS_ACCESS_KEY_ID` | Infrastructure deployment |
| `TARGET_AWS_SECRET_ACCESS_KEY` | Infrastructure deployment |

---

## 2. cert-manager Gateway API Support

**Problem:** ACME HTTP-01 challenges fail -- cert-manager does not enable Gateway API by default.

**Symptom:** `gateway api is not enabled, please pass the --enable-gateway-api flag`

**Solution:**

```bash
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version v1.17.1 \
  --set crds.enabled=true \
  --set config.enableGatewayAPI=true
```

---

## 3. ACME Challenges Failing for Apex Domain

**Problem:** Let's Encrypt issues certificate for `www.abdallahfekry.com` but not the apex domain.

**Root Cause:** Apex domain A records point to wrong IPs (not the EKS LoadBalancer). Only the `www` CNAME is correct.

**Solution (applied):** Use `www` subdomain only for both the certificate and gateway listener. The apex domain requires DNS correction in GoDaddy (CNAME/Alias to the ELB, or URL forwarding to `https://www.abdallahfekry.com`).

---

## 4. Backend CrashLoopBackOff

**Problem:** Backend pods fail with `django.db.utils.OperationalError: could not connect to server`.

**Root Cause:** `DATABASE_URL` in the Kubernetes secret points to a stale or incorrect RDS endpoint.

**Solution:**

```bash
# Get correct endpoint
aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,Endpoint.Address]' --output table

# Update .env, then recreate the secret
kubectl delete secret reddit-app-secret -n reddit-app
kubectl create secret generic reddit-app-secret \
  --from-env-file=argocd/install/.env -n reddit-app

# Restart pods
kubectl rollout restart deployment reddit-backend -n reddit-app
```

---

## 5. Gateway HTTPS Listener Invalid

**Problem:** Gateway shows `InvalidCertificateRef` because the TLS secret does not exist yet.

**Root Cause:** cert-manager has not finished issuing the certificate.

**Solution:** Wait for cert-manager to complete the ACME challenge. Verify with:

```bash
kubectl get certificates -n default
kubectl describe certificate reddit-tls-cert -n default
```

The gateway will become ready automatically once the secret is created.

---

## 6. Backend Health Probes Returning 400

**Problem:** Kubelet health probes fail with HTTP 400 because the Pod IP is not in Django `ALLOWED_HOSTS`.

**Solution (applied):**

1. Add `localhost` and `127.0.0.1` to `DJANGO_ALLOWED_HOSTS` in `helm-charts/backend/values.yaml`.
2. Set `Host: localhost` header on liveness and readiness probes in the deployment template.

```yaml
livenessProbe:
  httpGet:
    path: /health/liveness/
    port: 8000
    httpHeaders:
      - name: Host
        value: localhost
```

---

## 7. ArgoCD Sync Failures

**Problem:** Application stuck in `Progressing` or `Degraded` state.

**Diagnosis:**

```bash
kubectl describe application <app-name> -n argocd | grep -A10 "Message:"
kubectl get rs -n reddit-app
```

**Resolution steps:**

1. Delete old stuck ReplicaSets with `0 READY` but `DESIRED > 0`.
2. Scale deployment to 0 then back to desired count.
3. Force hard refresh: `kubectl patch application <app> -n argocd --type=merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'`

---

## Quick Diagnostic Commands

```bash
kubectl get pods -A
kubectl get applications -n argocd
kubectl get certificates -n default
kubectl get gateway -n default
kubectl get httproute -A
kubectl logs -f deployment/reddit-backend -n reddit-app
curl -sI https://www.abdallahfekry.com
curl -sI https://www.abdallahfekry.com/api/communities/
```
