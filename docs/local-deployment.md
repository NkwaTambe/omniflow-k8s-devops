# Local Deployment Guide

Complete guide for deploying OmniFlow Frontend to a local Kubernetes cluster using kind, tested end-to-end.

---

## How Helm, Kubernetes, and Terraform Relate

This project provides **three ways** to deploy the same application to Kubernetes. They all create identical K8s resources but differ in abstraction level:

```
┌──────────────────────────────────────────────────────────┐
│                    Terraform (Highest)                    │
│  Declarative IaC. Manages K8s resources + Helm releases  │
│  via providers. Best for multi-env parity & drift fix.   │
│                         │                                │
│                         ▼                                │
│                    Helm (Middle)                          │
│  Templated K8s manifests. Package + version releases.    │
│  Best for sharing charts and rollback via helm upgrade.  │
│                         │                                │
│                         ▼                                │
│              Raw K8s Manifests (Lowest)                   │
│  YAML files applied directly via kubectl. Simplest,     │
│  no templating. Best for learning and quick debugging.   │
└──────────────────────────────────────────────────────────┘
```

| Aspect | K8s Manifests | Helm | Terraform |
|--------|---------------|------|-----------|
| **What it is** | Raw YAML files | Templated chart + values | IaC with K8s provider |
| **Templating** | None (use Kustomize overlays) | Go templates + `values.yaml` | HCL variables + modules |
| **State management** | None (imperative) | Release history in cluster | `terraform.tfstate` file |
| **Rollback** | `kubectl rollout undo` | `helm rollback` | `terraform apply` (re-converge) |
| **Environment parity** | Kustomize overlays | values-dev/staging/prod.yaml | Separate environment configs |
| **Drift detection** | Manual | Manual | Automatic (`terraform plan`) |
| **Idempotency** | No (re-apply may differ) | Partial (upgrade is idempotent) | Yes (guaranteed same result) |
| **Use case** | Quick testing, debugging | Production deployments, packaging | Full lifecycle management, compliance |

**Recommendation:** Use **K8s manifests** for learning, **Helm** for CI/CD pipelines, and **Terraform** when you need drift detection and multi-environment parity.

---

## Prerequisites

| Tool | Version | Purpose | Install |
|------|---------|---------|---------|
| [Docker](https://docs.docker.com/get-docker/) | 20+ | Container runtime | System package |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.29+ | Kubernetes CLI | `snap install kubectl` |
| [Helm](https://helm.sh/docs/intro/install/) | 3.14+ | K8s package manager | `snap install helm` |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start/) | 0.20+ | Local K8s cluster | [Install script](https://kind.sigs.k8s.io/docs/user/quick-start/#installing-from-release-binaries) |
| [Terraform](https://developer.hashicorp.com/terraform/install) | 1.5+ | Infrastructure as Code | [HashiCorp repo](https://developer.hashicorp.com/terraform/install) |
| [Kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/) | 5+ | K8s manifest overlays (optional) | Built into kubectl |

Verify installations:

```bash
docker version --format '{{.Server.Version}}'
kubectl version --client --short 2>/dev/null || kubectl version --client
helm version --short
kind version
terraform version
```

---

## Step 1: Create the kind Cluster

Create a file `kind-config.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
```

```bash
kind create cluster --name omniflow --config kind-config.yaml --wait 120s
```

Verify:

```bash
kubectl get nodes
# NAME                     STATUS   ROLES           AGE   VERSION
# omniflow-control-plane   Ready    control-plane   60s   v1.29.2
# omniflow-worker          Ready    <none>          40s   v1.29.2
```

> **Note:** Port 80/443 mappings are omitted because they may conflict with local services. Use `kubectl port-forward` instead (shown below).

---

## Step 2: Build and Load the Container Image

```bash
# Build the image
docker build -t ghcr.io/nkwatambe/omniflow-k8s-devops:local ./src

# Load it into the kind cluster nodes
kind load docker-image ghcr.io/nkwatambe/omniflow-k8s-devops:local --name omniflow
```

> **Why `:local` tag?** The base manifests use `:latest` by default. For local dev, we use `:local` to avoid trying to pull from a remote registry, and set `imagePullPolicy: Never` so Kubernetes uses the image already loaded into kind.

---

## Step 3: Deploy (Choose One Method)

### Option A: Raw K8s Manifests

```bash
# Apply namespace first (avoid race condition with other resources)
kubectl apply -f k8s/base/namespace.yaml
sleep 2

# Apply the remaining manifests (exclude kustomization.yaml)
kubectl apply -f k8s/base/serviceaccount.yaml \
  -f k8s/base/configmap.yaml \
  -f k8s/base/deployment.yaml \
  -f k8s/base/service.yaml \
  -f k8s/base/hpa.yaml \
  -f k8s/base/networkpolicy.yaml

# Patch for local image
kubectl set image deployment/omniflow-frontend \
  omniflow-frontend=ghcr.io/nkwatambe/omniflow-k8s-devops:local \
  -n omniflow
kubectl patch deployment omniflow-frontend -n omniflow \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "Never"}]'
```

**Or use Kustomize overlay for dev:**

```bash
kubectl apply -k k8s/overlays/dev/
kubectl set image deployment/omniflow-frontend \
  omniflow-frontend=ghcr.io/nkwatambe/omniflow-k8s-devops:local \
  -n omniflow-dev
kubectl patch deployment omniflow-frontend -n omniflow-dev \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "Never"}]'
```

### Option B: Helm

```bash
helm install omniflow-frontend ./helm/omniflow-frontend \
  --namespace omniflow \
  --create-namespace \
  --set image.tag=local \
  --set image.pullPolicy=Never \
  --set ingress.enabled=false \
  --set replicaCount=1 \
  --set autoscaling.enabled=false \
  --set topologySpreadConstraints.enabled=false
```

**Or use the dev values file:**

```bash
helm install omniflow-frontend ./helm/omniflow-frontend \
  --namespace omniflow-dev \
  --create-namespace \
  -f ./helm/omniflow-frontend/values-dev.yaml \
  --set image.tag=local \
  --set image.pullPolicy=Never \
  --set ingress.enabled=false
```

### Option C: Terraform (Kubernetes Provider)

```bash
cd terraform/environments/dev

# Initialize
terraform init

# Apply (use kind-omniflow as the kube context)
terraform apply -auto-approve -var="kube_context=kind-omniflow"

# Patch for local image (Terraform creates :dev tag by default)
kubectl set image deployment/omniflow-frontend \
  omniflow-frontend=ghcr.io/nkwatambe/omniflow-k8s-devops:local \
  -n omniflow-dev
kubectl patch deployment omniflow-frontend -n omniflow-dev \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "Never"}]'
```

**Terraform module structure:**

```
terraform/
├── modules/
│   ├── namespace/        # Kubernetes namespace with labels
│   ├── frontend/         # Deployment, Service, HPA, NetworkPolicy, ConfigMap, SA
│   ├── ingress/          # Ingress with TLS and annotations
│   └── monitoring/       # Prometheus/Grafana via Helm release
└── environments/
    ├── dev/              # 1 replica, minimal resources, no TLS
    ├── staging/          # 2 replicas, moderate resources, TLS
    └── prod/             # 3 replicas, full resources, TLS, monitoring
```

**Environment parity:**

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

**Idempotency:**

```bash
terraform apply -auto-approve -var="kube_context=kind-omniflow"
terraform plan -var="kube_context=kind-omniflow"  # Should show "No changes"
terraform apply -auto-approve -var="kube_context=kind-omniflow"  # No changes applied
```

---

## Step 4: Verify the Deployment

### Check Pod Status

```bash
kubectl get pods -n omniflow
# NAME                                 READY   STATUS    RESTARTS   AGE
# omniflow-frontend-xxxxxxxxxx-xxxxx   1/1     Running   0          60s
```

### Check Deployment Rollout

```bash
kubectl rollout status deployment/omniflow-frontend -n omniflow
# deployment "omniflow-frontend" successfully rolled out
```

### Test the Health Endpoint

```bash
kubectl port-forward svc/omniflow-frontend -n omniflow 3000:80
# In another terminal:
curl http://localhost:3000/health
# healthy
```

### Test the Application

```bash
curl http://localhost:3000/
# Returns the HTML page with "Vite + React" heading
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

---

## Step 5: Access the Application

**Via port-forward (recommended for kind):**

```bash
kubectl port-forward svc/omniflow-frontend -n omniflow 3000:80
```

Open http://localhost:3000

> **How port forwarding works:** The Service exposes port 80 (ClusterIP), which routes to the pod's named port `http` (containerPort 8080). `kubectl port-forward` binds your local port 3000 to the Service port 80. The nginx container listens on port 8080 internally because it runs as a non-root user (UID 1001) which cannot bind to privileged ports (< 1024).

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
# Build a new image
docker build -t ghcr.io/nkwatambe/omniflow-k8s-devops:local ./src
kind load docker-image ghcr.io/nkwatambe/omniflow-k8s-devops:local --name omniflow

# Restart pods to pick up the new image
kubectl rollout restart deployment/omniflow-frontend -n omniflow
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

### Pod CrashLoopBackOff — Permission Denied on Port 80

**Symptom:** `bind() to 0.0.0.0:80 failed (13: Permission denied)`

**Cause:** The container runs as non-root user (UID 1001). Linux prevents non-root users from binding to ports below 1024.

**Fix:** The Dockerfile and nginx.conf are configured to use port 8080 internally. The Service maps port 80 → 8080. If you see this error, ensure `nginx.conf` has `listen 8080` and the Dockerfile has `EXPOSE 8080`.

### Pod ImagePullBackOff

**Cause:** Kubernetes tries to pull the image from a remote registry but it only exists locally.

**Fix:**

```bash
# Ensure image is loaded into kind
kind load docker-image ghcr.io/nkwatambe/omniflow-k8s-devops:local --name omniflow

# Set imagePullPolicy to Never
kubectl patch deployment omniflow-frontend -n omniflow \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "Never"}]'
```

### Ingress Not Working

```bash
# Install ingress controller in kind
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s

# Check ingress
kubectl get ingress -n omniflow
kubectl describe ingress -n omniflow
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
kubectl delete -f k8s/base/deployment.yaml -f k8s/base/service.yaml -f k8s/base/configmap.yaml -f k8s/base/hpa.yaml -f k8s/base/networkpolicy.yaml -f k8s/base/serviceaccount.yaml
kubectl delete -f k8s/base/namespace.yaml

# Using Terraform
cd terraform/environments/dev
terraform destroy -auto-approve -var="kube_context=kind-omniflow"
```

### Delete Cluster

```bash
kind delete cluster --name omniflow
```

---

## Architecture Diagram

```
                    ┌──────────────────────────────────────┐
                    │         kind K8s Cluster              │
                    │                                      │
  Browser ─────────▶│  ┌────────────────────────┐          │
  localhost:3000    │  │  kubectl port-forward   │          │
  (port-forward)    │  │  3000 → Service:80      │          │
                    │  └───────────┬────────────┘          │
                    │              │                        │
                    │  ┌───────────▼────────────┐          │
                    │  │  Service (ClusterIP)    │          │
                    │  │  port 80 → target 8080  │          │
                    │  └───────────┬────────────┘          │
                    │              │                        │
                    │  ┌───────────▼────────────┐          │
                    │  │  Deployment (pods)      │          │
                    │  │  omniflow-frontend      │          │
                    │  │  containerPort: 8080    │          │
                    │  │  (non-root, UID 1001)  │          │
                    │  └────────────────────────┘          │
                    │                                      │
                    │  ┌────────────────────────┐          │
                    │  │  HPA (1-3 replicas)    │          │
                    │  │  CPU: 70%  Mem: 80%    │          │
                    │  └────────────────────────┘          │
                    │                                      │
                    │  ┌────────────────────────┐          │
                    │  │  NetworkPolicy         │          │
                    │  │  Ingress: from same NS │          │
                    │  │  Egress: DNS only      │          │
                    │  └────────────────────────┘          │
                    └──────────────────────────────────────┘

  Port flow: Browser:3000 → port-forward → Service:80 → Pod:8080 (nginx)
```
