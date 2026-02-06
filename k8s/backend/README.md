# Backend Components

Backend components for the Reddit Clone application.

## Files

- **deployment.yaml**: Deployment configuration for the Backend
- **service.yaml**: Service configuration for accessing the Backend
- **configmap.yaml**: ConfigMap for environment variables

## Specifications

- **Image**: ECR repository backend-app
- **Port**: 8000
- **Service Port**: 8000
- **Replicas**: 2
- **Resources**:
  - Requests: 256Mi RAM, 200m CPU
  - Limits: 512Mi RAM, 500m CPU

## Deployment

```bash
# Deploy Backend only
kubectl apply -k .

# Or
kubectl apply -f .
```

## Customization

⚠️ **Important**: Update environment variables in `deployment.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://user:password@postgres:5432/reddit"
  - name: PORT
    value: "8000"
```

📝 **Note**: For production, use Kubernetes Secrets to securely store database credentials.
