# Gateway Components

Gateway and Routing components for the Reddit Clone application.

## Files

- **gateway.yaml**: Gateway configuration
- **httproute.yaml**: HTTPRoute configuration for routing

## Specifications

### Gateway
- **Name**: reddit-gateway
- **Protocol**: HTTP
- **Port**: 80
- **GatewayClass**: nginx

### HTTPRoute
- **Name**: reddit-httproute
- **Hostname**: reddit.local
- **Routes**:
  - `/api/*` → Backend Service (Port 8000)
  - `/*` → Frontend Service (Port 80)

## Prerequisites

Gateway API CRDs must be installed first:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
```

## Deployment

```bash
# Deploy Gateway only
kubectl apply -k .

# Or
kubectl apply -f .
```

## Customization

### Change the Hostname

Edit `httproute.yaml`:

```yaml
spec:
  hostnames:
    - "your-domain.com"
```

### Add HTTPS

Edit `gateway.yaml`:

```yaml
listeners:
  - name: https
    protocol: HTTPS
    port: 443
    tls:
      mode: Terminate
      certificateRefs:
        - name: your-tls-secret
```

### Add New Routes

Edit `httproute.yaml` and add new rules:

```yaml
rules:
  - matches:
      - path:
          type: PathPrefix
          value: /new-path
    backendRefs:
      - name: your-service
        port: 8080
```
