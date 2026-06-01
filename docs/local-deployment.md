# Local Deployment Guide

Complete guide for deploying OmniFlow Frontend to a local Kubernetes cluster using minikube or kind.

---

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [Docker](https://docs.docker.com/get-docker/) | 20+ | Container runtime |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.29+ | Kubernetes CLI |
| [Helm](https://helm.sh/docs/intro/install/) | 3.14+ | Kubernetes package manager |
| [minikube](https://minikube.sigs.k8s.io/docs/start/) or [kind](https://kind.sigs.k8s.io/docs/user/quick-start/) | Latest | Local K8s cluster |
| [Kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/) | 5+ | K8s manifest overlay tool (optional) |
| [Terraform](https://developer.hashicorp.com/terraform/install) | 1.5+ | Infrastructure as Code (Kubernetes provider) |

Verify installations:

```bash
docker version --format '{{.Server.Version}}'
kubectl version --client --short
helm version --short
minikube version --short
```

---

## Option A: Deploy with minikube

### 1. Start the Cluster

```bash
minikube start \
  --cpus=4 \
  --memory=8192 \
  --disk-size=30g \
  --kubernetes-version=v1.29.0 \
  --driver=docker
```

Verify:

```bash
kubectl get nodes
# NAME       STATUS   ROLES           AGE   VERSION
# minikube   Ready    control-plane   30s   v1.29.0
```

### 2. Enable Addons

```bash
minikube addons enable ingress
minikube addons enable metrics-server
minikube addons enable dashboard
```

### 3. Build the Container Image

Point Docker to minikube's Docker daemon so the image is available inside the cluster:

```bash
eval $(minikube docker-env)
docker build -t ghcr.io/nkwatambe/omniflow-k8s-devops:local ./src
```

Reset Docker env after building:

```bash
eval $(minikube docker-env -u)
```

### 4. Deploy Using Raw Manifests

```bash
# Apply all base manifests
kubectl apply -f k8s/base/

# Or apply per-environment overlay
kubectl apply -k k8s/overlays/dev/
```

For the local image, patch the deployment to use it and set `imagePullPolicy: Never`:

```bash
kubectl patch deployment omniflow-frontend -n omniflow \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "ghcr.io/nkwatambe/omniflow-k8s-devops:local"}, {"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "Never"}]'
```

### 5. Deploy Using Helm

```bash
helm install omniflow-frontend ./helm/omniflow-frontend \
  --namespace omniflow \
  --create-namespace \
  --set image.tag=local \
  --set image.pullPolicy=Never \
  --set ingress.enabled=false
```

### 6. Access the Application

**Via port-forward (quick access):**

```bash
kubectl port-forward svc/omniflow-frontend -n omniflow 3000:80
```

Open http://localhost:3000

**Via minikube tunnel (for LoadBalancer/Ingress):**

```bash
sudo minikube tunnel
```

Then add to `/etc/hosts`:

```
127.0.0.1 omniflow.local
```

Open https://omniflow.local

**Via minikube service command:**

```bash
minikube service omniflow-frontend -n omniflow
```

This opens the application in your browser automatically.

---

## Option B: Deploy with kind

### 1. Create the Cluster

Create a file `kind-config.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
  - role: worker
  - role: worker
```

```bash
kind create cluster --name omniflow --config kind-config.yaml
```

### 2. Load the Image into kind

```bash
docker build -t ghcr.io/nkwatambe/omniflow-k8s-devops:local ./src
kind load docker-image ghcr.io/nkwatambe/omniflow-k8s-devops:local --name omniflow
```

### 3. Install Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s
```

### 4. Deploy the Application

```bash
# Using Helm
helm install omniflow-frontend ./helm/omniflow-frontend \
  --namespace omniflow \
  --create-namespace \
  --set image.tag=local \
  --set image.pullPolicy=Never \
  -f ./helm/omniflow-frontend/values-dev.yaml

# Or using raw manifests
kubectl apply -k k8s/overlays/dev/
kubectl patch deployment omniflow-frontend -n omniflow-dev \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "Never"}]'
```

### 5. Access the Application

Add to `/etc/hosts`:

```
127.0.0.1 omniflow.dev.local
```

Open http://omniflow.dev.local

Or use port-forward:

```bash
kubectl port-forward svc/omniflow-frontend -n omniflow-dev 3000:80
# Open http://localhost:3000
```

---

## Verify the Deployment

### Check Pod Status

```bash
kubectl get pods -n omniflow
# NAME                                  READY   STATUS    RESTARTS   AGE
# omniflow-frontend-xxxxxxxxxx-xxxxx    1/1     Running   0          60s
```

### Check Deployment Rollout

```bash
kubectl rollout status deployment/omniflow-frontend -n omniflow
# deployment "omniflow-frontend" successfully rolled out
```

### Check Health Endpoint

```bash
kubectl port-forward svc/omniflow-frontend -n omniflow 3000:80 &
curl http://localhost:3000/health
# healthy
```

### Check Services and Endpoints

```bash
kubectl get svc -n omniflow
kubectl get endpoints -n omniflow
```

### Check Logs

```bash
kubectl logs -l app.kubernetes.io/name=omniflow-frontend -n omniflow --follow
```

### Check Resource Usage

```bash
kubectl top pods -n omniflow
kubectl top nodes
```

---

## Scaling

### Manual Scaling

```bash
kubectl scale deployment omniflow-frontend -n omniflow --replicas=5
```

### Verify HPA

```bash
kubectl get hpa -n omniflow
# NAME                 REFERENCE                       TARGETS         MINPODS   MAXPODS   REPLICAS
# omniflow-frontend    Deployment/omniflow-frontend    0%/70%, 0%/80%  3         10        3
```

### Generate Load to Test HPA

```bash
kubectl run load-generator --image=busybox --restart=Never -- \
  /bin/sh -c "while true; do wget -q -O- http://omniflow-frontend.omniflow.svc.cluster.local; done"
```

Watch HPA scale up:

```bash
kubectl get hpa -n omniflow -w
```

Clean up:

```bash
kubectl delete pod load-generator
```

---

## Update the Deployment

### Rolling Update (Helm)

```bash
# After building a new image
eval $(minikube docker-env)
docker build -t ghcr.io/nkwatambe/omniflow-k8s-devops:local ./src
eval $(minikube docker-env -u)

# Upgrade the release
helm upgrade omniflow-frontend ./helm/omniflow-frontend \
  --namespace omniflow \
  --set image.tag=local \
  --set image.pullPolicy=Never \
  --set ingress.enabled=false
```

### Rolling Update (kubectl)

```bash
kubectl set image deployment/omniflow-frontend \
  omniflow-frontend=ghcr.io/nkwatambe/omniflow-k8s-devops:local \
  -n omniflow
```

### Rollback

```bash
# Check rollout history
kubectl rollout history deployment/omniflow-frontend -n omniflow

# Rollback to previous revision
kubectl rollout undo deployment/omniflow-frontend -n omniflow

# Rollback to specific revision
kubectl rollout undo deployment/omniflow-frontend -n omniflow --to-revision=2
```

---

## Troubleshooting

### Pod CrashLoopBackOff

```bash
kubectl describe pod <pod-name> -n omniflow
kubectl logs <pod-name> -n omniflow --previous
```

### Image Pull Back Off

Ensure the image is built in the correct Docker daemon:

```bash
# For minikube
eval $(minikube docker-env)
docker images | grep omniflow

# For kind
kind load docker-image ghcr.io/nkwatambe/omniflow-k8s-devops:local --name omniflow
```

Also verify `imagePullPolicy: Never` is set for local images.

### Ingress Not Working

```bash
kubectl get ingress -n omniflow
kubectl describe ingress -n omniflow
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

### HPA Not Scaling

```bash
kubectl describe hpa omniflow-frontend -n omniflow
kubectl top pods -n omniflow
```

Verify metrics-server is running:

```bash
kubectl get deployment metrics-server -n kube-system
```

---

## Clean Up

### Delete Application

```bash
# Using Helm
helm uninstall omniflow-frontend --namespace omniflow

# Using kubectl
kubectl delete -f k8s/base/
# or
kubectl delete -k k8s/overlays/dev/
```

### Delete Cluster

```bash
# minikube
minikube delete

# kind
kind delete cluster --name omniflow
```

---

## Option C: Deploy with Terraform (Kubernetes Provider)

Terraform manages all Kubernetes resources declaratively using the Kubernetes and Helm providers.

### 1. Initialize Terraform

```bash
cd terraform/environments/dev
terraform init
```

### 2. Build and Load the Image

```bash
# For minikube
eval $(minikube docker-env)
docker build -t ghcr.io/nkwatambe/omniflow-k8s-devops:dev ../../src
eval $(minikube docker-env -u)

# For kind
docker build -t ghcr.io/nkwatambe/omniflow-k8s-devops:dev ../../src
kind load docker-image ghcr.io/nkwatambe/omniflow-k8s-devops:dev --name omniflow
```

### 3. Plan and Apply

```bash
# Preview changes
terraform plan -var="kube_context=minikube"

# Apply infrastructure
terraform apply -var="kube_context=minikube"
```

### 4. Verify

```bash
kubectl get all -n omniflow-dev
kubectl get ingress -n omniflow-dev
```

### 5. Access the Application

```bash
kubectl port-forward svc/omniflow-frontend -n omniflow-dev 3000:80
# Open http://localhost:3000
```

### 6. Destroy (Clean Up)

```bash
terraform destroy -var="kube_context=minikube"
```

### Terraform Module Structure

```
terraform/
├── modules/
│   ├── namespace/        # Kubernetes namespace
│   ├── frontend/         # Deployment, Service, HPA, NetworkPolicy, ConfigMap, SA
│   ├── ingress/          # Ingress with TLS
│   └── monitoring/       # Prometheus/Grafana via Helm
└── environments/
    ├── dev/              # 1 replica, minimal resources, no TLS
    ├── staging/          # 2 replicas, moderate resources, TLS
    └── prod/             # 3 replicas, full resources, TLS, monitoring
```

### Environment Parity

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| Replicas | 1 | 2 | 3 |
| CPU request | 25m | 50m | 100m |
| Memory request | 32Mi | 64Mi | 128Mi |
| CPU limit | 100m | 200m | 500m |
| Memory limit | 64Mi | 128Mi | 256Mi |
| HPA max | 3 | 5 | 10 |
| TLS | Off | On | On |
| Monitoring | Off | Off | On |

### Idempotency

Running `terraform apply` multiple times produces the same result:

```bash
terraform apply -auto-approve
terraform plan  # Should show "No changes"
terraform apply -auto-approve  # No changes applied
```

---

## Architecture Diagram

```
                    ┌──────────────────────────────────┐
                    │        Local K8s Cluster          │
                    │                                  │
  Browser ─────────▶│  ┌────────────────────────┐      │
  localhost:3000    │  │  Ingress Controller    │      │
  or                │  │  (nginx-ingress)       │      │
  omniflow.local    │  └───────────┬────────────┘      │
                    │              │                    │
                    │  ┌───────────▼────────────┐      │
                    │  │  Service (ClusterIP)    │      │
                    │  │  omniflow-frontend:80  │      │
                    │  └───────────┬────────────┘      │
                    │              │                    │
                    │  ┌───────────▼────────────┐      │
                    │  │  Deployment (3 pods)   │      │
                    │  │  omniflow-frontend     │      │
                    │  │  ├─ Pod 1 (nginx)      │      │
                    │  │  ├─ Pod 2 (nginx)      │      │
                    │  │  └─ Pod 3 (nginx)      │      │
                    │  └────────────────────────┘      │
                    │                                  │
                    │  ┌────────────────────────┐      │
                    │  │  HPA (3-10 replicas)   │      │
                    │  │  CPU: 70%  Mem: 80%    │      │
                    │  └────────────────────────┘      │
                    └──────────────────────────────────┘
```
