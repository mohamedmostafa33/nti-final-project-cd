#!/bin/bash

# ArgoCD Installation Script
# This script installs ArgoCD and applies custom configurations

set -e

echo "Installing ArgoCD..."

# Create argocd namespace
echo "Creating argocd namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
echo "Installing ArgoCD from official manifests..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
echo "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=600s deployment/argocd-repo-server -n argocd
kubectl wait --for=condition=available --timeout=600s deployment/argocd-applicationset-controller -n argocd

# Apply custom configurations
echo "Applying custom configurations..."
kubectl apply -f argocd/install/argocd-config.yaml

# Get initial admin password
echo ""
echo "ArgoCD installed successfully!"
echo ""
echo "To get the initial admin password, run:"
echo "   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d && echo"
echo ""
echo "To access the ArgoCD UI, run:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "Then open: https://localhost:8080"
echo "   Username: admin"
echo ""
