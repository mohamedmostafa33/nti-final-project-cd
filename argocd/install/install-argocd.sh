#!/bin/bash

# ArgoCD Installation Script
# This script installs prerequisites, ArgoCD, and deploys all applications
#
# Prerequisites:
#   - kubectl configured with EKS cluster access
#   - helm v3 installed
#
# Usage:
#   ./install-argocd.sh
#
# After running this script, create the app secret:
#   kubectl create secret generic reddit-app-secret \
#     --from-literal=DJANGO_SECRET_KEY='...' \
#     --from-literal=AWS_ACCESS_KEY_ID='...' \
#     --from-literal=AWS_SECRET_ACCESS_KEY='...' \
#     --from-literal=DATABASE_URL='postgresql://...' \
#     -n reddit-app

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CD_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "============================================"
echo "  Step 1: Install Gateway API CRDs"
echo "============================================"
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
echo "Gateway API CRDs installed."

echo ""
echo "============================================"
echo "  Step 2: Install NGINX Gateway Fabric"
echo "============================================"
helm repo add nginx-gateway https://nginx-gateway-fabric.nginx.org 2>/dev/null || true
helm repo update
if helm status nginx-gateway -n nginx-gateway &>/dev/null; then
  echo "NGINX Gateway Fabric already installed, upgrading..."
  helm upgrade nginx-gateway nginx-gateway-fabric/nginx-gateway-fabric \
    -n nginx-gateway \
    --set service.type=LoadBalancer
else
  helm install nginx-gateway nginx-gateway-fabric/nginx-gateway-fabric \
    -n nginx-gateway --create-namespace \
    --set service.type=LoadBalancer
fi
echo "NGINX Gateway Fabric ready."

echo ""
echo "============================================"
echo "  Step 3: Install ArgoCD"
echo "============================================"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "Installing ArgoCD from official manifests..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=600s deployment/argocd-repo-server -n argocd
kubectl wait --for=condition=available --timeout=600s deployment/argocd-applicationset-controller -n argocd

echo "Applying custom configurations..."
kubectl apply -f "$SCRIPT_DIR/argocd-config.yaml"

echo ""
echo "============================================"
echo "  Step 4: Deploy Applications (App of Apps)"
echo "============================================"
kubectl apply -f "$CD_ROOT/argocd/root-app.yaml"
echo "Root application applied. ArgoCD will now sync all apps."

echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "IMPORTANT: Create the application secret before pods start:"
echo "   kubectl create secret generic reddit-app-secret \\"
echo "     --from-literal=DJANGO_SECRET_KEY='<value>' \\"
echo "     --from-literal=AWS_ACCESS_KEY_ID='<value>' \\"
echo "     --from-literal=AWS_SECRET_ACCESS_KEY='<value>' \\"
echo "     --from-literal=DATABASE_URL='postgresql://user:pass@host:5432/db' \\"
echo "     -n reddit-app"
echo ""
echo "ArgoCD admin password:"
echo "   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d && echo"
echo ""
echo "Access ArgoCD UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Then open: https://localhost:8080  (user: admin)"
echo ""
echo "Check Gateway LoadBalancer (for DNS setup):"
echo "   kubectl get svc -n nginx-gateway"
echo ""
