# Backend Components

مكونات Backend الخاصة بتطبيق Reddit Clone.

## الملفات

- **deployment.yaml**: Deployment configuration للـ Backend
- **service.yaml**: Service configuration للوصول للـ Backend
- **kustomization.yaml**: Kustomize configuration

## المواصفات

- **Image**: mohamedmostafa33/backend:latest
- **Port**: 8000
- **Service Port**: 8000
- **Replicas**: 2
- **Resources**:
  - Requests: 256Mi RAM, 200m CPU
  - Limits: 512Mi RAM, 500m CPU

## النشر

```bash
# نشر Backend فقط
kubectl apply -k .

# أو
kubectl apply -f .
```

## التخصيص

⚠️ **مهم**: قم بتحديث متغيرات البيئة في `deployment.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://user:password@postgres:5432/reddit"
  - name: PORT
    value: "8000"
```

📝 **ملاحظة**: للإنتاج، استخدم Kubernetes Secrets لحفظ بيانات قاعدة البيانات بشكل آمن.
