#!/bin/bash

# Uninstall Script — run BEFORE terraform destroy
# This removes all K8s resources that could block infrastructure teardown
# (LoadBalancers, PVCs, finalizers, etc.)
#
# Handles stuck namespaces/CRDs by force-removing finalizers.

set -uo pipefail

# ── Helper: wait for a namespace to be fully deleted ──
wait_ns_gone() {
  local ns="$1" timeout="${2:-120}" elapsed=0
  if ! kubectl get namespace "$ns" &>/dev/null; then return 0; fi
  echo "  Waiting for namespace '$ns' to terminate (up to ${timeout}s)..."
  while kubectl get namespace "$ns" &>/dev/null; do
    if (( elapsed >= timeout )); then
      echo "  Namespace '$ns' stuck — force-removing finalizers..."
      kubectl get namespace "$ns" -o json \
        | jq '.spec.finalizers = []' \
        | kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - &>/dev/null || true
      sleep 3
      return 0
    fi
    sleep 3; elapsed=$((elapsed + 3))
  done
}

echo "============================================"
echo "  Step 1: Remove ArgoCD Applications"
echo "============================================"
# Remove finalizers first so ArgoCD doesn't block deletion
for app in $(kubectl get applications -n argocd -o name 2>/dev/null); do
  echo "  Removing finalizers from $app ..."
  kubectl patch "$app" -n argocd --type json \
    -p '[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
done
kubectl delete applications --all -n argocd --timeout=60s 2>/dev/null || true
echo "ArgoCD applications removed."

echo ""
echo "============================================"
echo "  Step 2: Delete app workloads & secrets"
echo "============================================"
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
kubectl delete gateway --all --all-namespaces --timeout=60s 2>/dev/null || true
kubectl delete httproute --all --all-namespaces --timeout=60s 2>/dev/null || true
echo "Gateway resources removed."

echo ""
echo "============================================"
echo "  Step 4: Uninstall NGINX Gateway Fabric"
echo "============================================"
helm uninstall nginx-gateway -n nginx-gateway 2>/dev/null || true
kubectl delete namespace nginx-gateway --timeout=60s 2>/dev/null || true
wait_ns_gone nginx-gateway 90
echo "NGINX Gateway Fabric removed."

echo ""
echo "============================================"
echo "  Step 5: Uninstall cert-manager"
echo "============================================"
kubectl delete clusterissuer letsencrypt-prod 2>/dev/null || true
helm uninstall cert-manager -n cert-manager 2>/dev/null || true
kubectl delete namespace cert-manager --timeout=60s 2>/dev/null || true
wait_ns_gone cert-manager 90

# Clean up cert-manager CRDs
for crd in certificates.cert-manager.io certificaterequests.cert-manager.io clusterissuers.cert-manager.io issuers.cert-manager.io challenges.acme.cert-manager.io orders.acme.cert-manager.io; do
  if kubectl get crd "$crd" &>/dev/null; then
    kubectl delete crd "$crd" --timeout=30s 2>/dev/null || true
  fi
done
echo "cert-manager removed."

echo ""
echo "============================================"
echo "  Step 6: Uninstall ArgoCD"
echo "============================================"
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml 2>/dev/null || true
kubectl delete namespace argocd --timeout=60s 2>/dev/null || true
wait_ns_gone argocd 90

# Force-clean stuck ArgoCD CRDs (prevents "CRD is terminating" on reinstall)
for crd in applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io; do
  if kubectl get crd "$crd" &>/dev/null; then
    kubectl patch crd "$crd" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
    kubectl delete crd "$crd" --timeout=30s 2>/dev/null || true
  fi
done

# Clean up cluster-scoped leftovers
for res in argocd-application-controller argocd-applicationset-controller argocd-server; do
  kubectl delete clusterrole "$res" --ignore-not-found 2>/dev/null || true
  kubectl delete clusterrolebinding "$res" --ignore-not-found 2>/dev/null || true
done
echo "ArgoCD removed."

echo ""
echo "============================================"
echo "  Step 7: Remove Gateway API CRDs"
echo "============================================"
kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml 2>/dev/null || true
echo "Gateway API CRDs removed."

echo ""
echo "============================================"
echo "  Step 8: Delete app namespace"
echo "============================================"
kubectl delete namespace reddit-app --timeout=60s 2>/dev/null || true
wait_ns_gone reddit-app 90
echo "Namespace reddit-app removed."

echo ""
echo "============================================"
echo "  Step 9: Verify clean state"
echo "============================================"
LB_SERVICES=$(kubectl get svc --all-namespaces -o json 2>/dev/null | grep -c '"LoadBalancer"' || true)
if [ "$LB_SERVICES" -gt 0 ]; then
  echo "WARNING: $LB_SERVICES LoadBalancer service(s) still exist!"
  kubectl get svc --all-namespaces | grep LoadBalancer
else
  echo "No LoadBalancer services found."
fi

REMAINING=$(kubectl get namespaces -o name 2>/dev/null | grep -cE 'argocd|nginx-gateway|reddit-app|cert-manager' || true)
if [ "$REMAINING" -gt 0 ]; then
  echo "WARNING: Some namespaces still exist:"
  kubectl get namespaces | grep -E 'argocd|nginx-gateway|reddit-app|cert-manager'
else
  echo "All application namespaces cleaned."
fi

echo ""
echo "============================================"
echo "  Cleanup Complete!"
echo "============================================"
echo ""
echo "You can now safely run:"
echo "   cd nti-final-project-infra/infra && terraform destroy"
echo ""
