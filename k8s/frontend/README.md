# Frontend Components

Frontend components for the Reddit Clone application.

## Files

- **deployment.yaml**: Deployment configuration for the Frontend
- **service.yaml**: Service configuration for accessing the Frontend

## Specifications

- **Image**: ECR repository reddit-frontend
- **Port**: 3000
- **Service Port**: 80
- **Replicas**: 2
- **Resources**:
  - Requests: 128Mi RAM, 100m CPU
  - Limits: 256Mi RAM, 200m CPU

## Deployment

```bash
# Deploy Frontend only
kubectl apply -k .

# Or
kubectl apply -f .
```

## Customization

You can modify environment variables in `deployment.yaml`:

```yaml
env:
  - name: NEXT_PUBLIC_API_URL
    value: "http://reddit-backend-service:8000"
```
