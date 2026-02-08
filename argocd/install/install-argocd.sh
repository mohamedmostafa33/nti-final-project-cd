#!/bin/bash

# ArgoCD Installation Script
# Installs prerequisites, injects secrets, installs ArgoCD, and deploys all applications.
#
# Prerequisites:
#   - kubectl configured with EKS cluster access
#   - helm v3 installed
#   - A .env file (or environment variables) with the required secrets
#
# Usage:
#   ./install-argocd.sh                         # reads secrets from .env file
#   ./install-argocd.sh --env-file /path/.env   # custom .env path

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CD_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# ── Parse arguments ──
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file) ENV_FILE="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Load secrets from .env file if it exists ──
if [[ -f "$ENV_FILE" ]]; then
  echo "Loading secrets from $ENV_FILE"
  set -a; source "$ENV_FILE"; set +a
fi

# ── Validate required secrets ──
MISSING=()
for var in DJANGO_SECRET_KEY AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY DATABASE_URL; do
  if [[ -z "${!var:-}" ]]; then MISSING+=("$var"); fi
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "ERROR: Missing required secrets: ${MISSING[*]}"
  echo ""
  echo "Either export them or create $SCRIPT_DIR/.env with:"
  echo "  DJANGO_SECRET_KEY=..."
  echo "  AWS_ACCESS_KEY_ID=..."
  echo "  AWS_SECRET_ACCESS_KEY=..."
  echo "  DATABASE_URL=postgresql://user:pass@host:5432/db"
  exit 1
fi

echo "============================================"
echo "  Step 1: Install Gateway API CRDs"
echo "============================================"
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
echo "Gateway API CRDs installed."

echo ""
echo "============================================"
echo "  Step 2: Install NGINX Gateway Fabric"
echo "============================================"
if helm status nginx-gateway -n nginx-gateway &>/dev/null; then
  echo "NGINX Gateway Fabric already installed, upgrading..."
  helm upgrade nginx-gateway oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
    -n nginx-gateway
else
  helm install nginx-gateway oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
    -n nginx-gateway --create-namespace
fi
echo "NGINX Gateway Fabric ready."

echo ""
echo "============================================"
echo "  Step 3: Install cert-manager"
echo "============================================"
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
helm repo update jetstack

if helm status cert-manager -n cert-manager &>/dev/null; then
  echo "cert-manager already installed, upgrading..."
  helm upgrade cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --version v1.17.1 \
    --set crds.enabled=true \
    --set config.enableGatewayAPI=true
else
  helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version v1.17.1 \
    --set crds.enabled=true \
    --set config.enableGatewayAPI=true
fi

echo "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=180s
kubectl wait --for=condition=Available deployment/cert-manager-webhook -n cert-manager --timeout=180s
kubectl wait --for=condition=Available deployment/cert-manager-cainjector -n cert-manager --timeout=180s

# Create ClusterIssuer for Let's Encrypt (using Gateway API HTTP-01 solver)
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@abdallahfekry.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          gatewayHTTPRoute:
            parentRefs:
              - name: reddit-gateway
                namespace: default
                kind: Gateway
EOF
echo "cert-manager and Let's Encrypt ClusterIssuer installed."

echo ""
echo "============================================"
echo "  Step 4: Create App Namespace & Secret"
echo "============================================"
kubectl create namespace reddit-app --dry-run=client -o yaml | kubectl apply -f -

if kubectl get secret reddit-app-secret -n reddit-app &>/dev/null; then
  echo "Secret reddit-app-secret already exists, replacing..."
  kubectl delete secret reddit-app-secret -n reddit-app
fi

kubectl create secret generic reddit-app-secret \
  --from-literal=DJANGO_SECRET_KEY="$DJANGO_SECRET_KEY" \
  --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
  --from-literal=DATABASE_URL="$DATABASE_URL" \
  -n reddit-app
echo "Secret injected into reddit-app namespace."

echo ""
echo "============================================"
echo "  Step 5: Install ArgoCD"
echo "============================================"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "Installing ArgoCD from official manifests..."
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=600s deployment/argocd-repo-server -n argocd
kubectl wait --for=condition=available --timeout=600s deployment/argocd-applicationset-controller -n argocd

echo "Applying custom configurations..."
kubectl apply -f "$SCRIPT_DIR/argocd-config.yaml"

echo ""
echo "============================================"
echo "  Step 6: Deploy Applications (App of Apps)"
echo "============================================"
kubectl apply -f "$CD_ROOT/argocd/root-app.yaml"
echo "Root application applied. ArgoCD will now sync all apps."

echo ""
echo "============================================"
echo "  Step 7: Wait for Certificates"
echo "============================================"
echo "Waiting for TLS certificates to be issued (this may take 2-3 minutes)..."
echo "Certificates will be created by cert-manager when Gateway is deployed."
echo ""
echo "You can check certificate status with:"
echo "   kubectl get certificates -n default"
echo "   kubectl get certificaterequests -n default"

echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "<not yet available>")
echo "ArgoCD Credentials:"
echo "   User:     admin"
echo "   Password: $ARGOCD_PASS"
echo ""
echo "Access ArgoCD UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Then open: https://localhost:8080"
echo ""
echo "Check Gateway LoadBalancer (for DNS setup):"
echo "   kubectl get svc -n nginx-gateway"
echo ""
echo "Check TLS Certificates:"
echo "   kubectl get certificates -n default"
echo ""
echo "Once certificates are Ready, access your site at:"
echo "   https://www.abdallahfekry.com"
echo ""
