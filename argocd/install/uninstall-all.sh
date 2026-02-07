#!/bin/bash

# Uninstall Script — run BEFORE terraform destroy
# This removes all K8s resources that could block infrastructure teardown
# (LoadBalancers, PVCs, finalizers, etc.)

set -uo pipefail

echo "============================================"
echo "  Step 1: Remove ArgoCD Applications"
echo "============================================"
# Remove finalizers first so ArgoCD doesn't block deletion
for app in $(kubectl get applications -n argocd -o name 2>/dev/null); do
  echo "Removing finalizers from $app ..."
  kubectl patch "$app" -n argocd --type json \
    -p '[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
done

# Delete all ArgoCD applications
kubectl delete applications --all -n argocd --timeout=60s 2>/dev/null || true
echo "ArgoCD applications removed."

echo ""
echo "============================================"
echo "  Step 2: Delete app workloads and secrets"
echo "============================================"
# Delete everything in the app namespace
kubectl delete all --all -n reddit-app --timeout=60s 2>/dev/null || true
kubectl delete configmap --all -n reddit-app 2>/dev/null || true
kubectl delete secret --all -n reddit-app 2>/dev/null || true
kubectl delete jobs --all -n reddit-app 2>/dev/null || true
kubectl delete httproute --all -n reddit-app 2>/dev/null || true
echo "App workloads removed."

echo ""
echo "============================================"
echo "  Step 3: Delete Gateway resources"
echo "============================================"
kubectl delete gateway --all -n default --timeout=60s 2>/dev/null || true
kubectl delete httproute --all -n default --timeout=60s 2>/dev/null || true
echo "Gateway resources removed."

echo ""
echo "============================================"
echo "  Step 4: Uninstall NGINX Gateway Fabric"
echo "============================================"
# This removes the LoadBalancer service — critical before terraform destroy
helm uninstall nginx-gateway -n nginx-gateway 2>/dev/null || true
kubectl delete namespace nginx-gateway --timeout=120s 2>/dev/null || true
echo "NGINX Gateway Fabric removed."

echo ""
echo "============================================"
echo "  Step 5: Uninstall ArgoCD"
echo "============================================"
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml 2>/dev/null || true
kubectl delete namespace argocd --timeout=120s 2>/dev/null || true
echo "ArgoCD removed."

echo ""
echo "============================================"
echo "  Step 6: Remove Gateway API CRDs"
echo "============================================"
kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml 2>/dev/null || true
echo "Gateway API CRDs removed."

echo ""
echo "============================================"
echo "  Step 7: Delete app namespace"
echo "============================================"
kubectl delete namespace reddit-app --timeout=120s 2>/dev/null || true
echo "Namespace reddit-app removed."

echo ""
echo "============================================"
echo "  Step 8: Verify no LoadBalancers remain"
echo "============================================"
LB_SERVICES=$(kubectl get svc --all-namespaces -o json 2>/dev/null | grep -c '"LoadBalancer"' || true)
if [ "$LB_SERVICES" -gt 0 ]; then
  echo "WARNING: $LB_SERVICES LoadBalancer service(s) still exist!"
  echo "These may block terraform destroy. Listing:"
  kubectl get svc --all-namespaces | grep LoadBalancer
  echo ""
  echo "Delete them manually before running terraform destroy."
else
  echo "No LoadBalancer services found. Safe to run terraform destroy."
fi

echo ""
echo "============================================"
echo "  Cleanup Complete!"
echo "============================================"
echo ""
echo "You can now safely run:"
echo "   cd nti-final-project-infra/infra && terraform destroy"
echo ""
