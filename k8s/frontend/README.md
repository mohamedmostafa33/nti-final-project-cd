# Frontend Components

مكونات Frontend الخاصة بتطبيق Reddit Clone.

## الملفات

- **deployment.yaml**: Deployment configuration للـ Frontend
- **service.yaml**: Service configuration للوصول للـ Frontend
- **kustomization.yaml**: Kustomize configuration

## المواصفات

- **Image**: mohamedmostafa33/reddit-frontend:latest
- **Port**: 3000
- **Service Port**: 80
- **Replicas**: 2
- **Resources**:
  - Requests: 128Mi RAM, 100m CPU
  - Limits: 256Mi RAM, 200m CPU

## النشر

```bash
# نشر Frontend فقط
kubectl apply -k .

# أو
kubectl apply -f .
```

## التخصيص

يمكنك تعديل متغيرات البيئة في `deployment.yaml`:

```yaml
env:
  - name: REACT_APP_BACKEND_URL
    value: "http://reddit-backend-service:8000"
```
