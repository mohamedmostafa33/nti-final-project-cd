# Gateway Components

مكونات Gateway و Routing الخاصة بتطبيق Reddit Clone.

## الملفات

- **gateway.yaml**: Gateway configuration
- **httproute.yaml**: HTTPRoute configuration للـ routing
- **kustomization.yaml**: Kustomize configuration

## المواصفات

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

## المتطلبات

يجب تثبيت Gateway API CRDs أولاً:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
```

## النشر

```bash
# نشر Gateway فقط
kubectl apply -k .

# أو
kubectl apply -f .
```

## التخصيص

### تغيير الـ Hostname

عدّل `httproute.yaml`:

```yaml
spec:
  hostnames:
    - "your-domain.com"
```

### إضافة HTTPS

عدّل `gateway.yaml`:

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

### إضافة Routes جديدة

عدّل `httproute.yaml` وأضف rules جديدة:

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
