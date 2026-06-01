# Local Deployment Guide

Complete guide for deploying OmniFlow Frontend locally, explaining how kind, Kubernetes, Helm, and Terraform work **together** as one system.

---

## The Big Picture: How Everything Connects

```
┌─────────────────────────────────────────────────────────────────┐
│                        OmniFlow DevOps System                    │
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────────────┐│
│  │   Terraform   │──▶│     Helm     │──▶│    Kubernetes (K8s)   ││
│  │  (Provision)  │   │  (Package)   │   │   (Orchestrate)      ││
│  └──────┬───────┘   └──────┬───────┘   └──────────┬───────────┘│
│         │                  │                      │             │
│         │  Provisions      │  Installs app        │  Runs       │
│         │  infrastructure  │  as packaged release │  containers │
│         ▼                  ▼                      ▼             │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    kind Cluster                           │  │
│  │            (Local K8s = Simulates AWS EKS)                │  │
│  │                                                          │  │
│  │  Namespace ── ConfigMap ── Deployment ── Service ── HPA  │  │
│  │  NetworkPolicy ── Ingress ── ServiceAccount              │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### What Each Tool Does

| Tool | Role | Analogy | What it creates |
|------|------|---------|-----------------|
| **kind** | Local K8s cluster | The server/datacenter | A Kubernetes control-plane + worker nodes (Docker containers) |
| **Kubernetes** | Container orchestration | The operating system | Runs pods, manages networking, scaling, self-healing |
| **Helm** | Package manager | `apt`/`npm` for K8s | Bundles K8s manifests into versioned charts, manages releases |
| **Terraform** | Infrastructure as Code | The build script | Declares all K8s resources + calls Helm. Detects drift. Ensures idempotency |
| **k9s** | Cluster visualization | Task manager for K8s | Terminal UI to see pods, logs, events — everything running in the cluster |

### How They Work Together

They are **layers**, not alternatives. In the real system:

1. **kind** creates the K8s cluster (replaces AWS EKS for local dev)
2. **Terraform** provisions infrastructure ON that cluster — namespaces, deployments, services, HPA, network policies, AND Helm releases
3. **Helm** packages the application into a reusable chart that Terraform (or CI/CD) installs
4. **Kubernetes** orchestrates the running containers — scheduling, scaling, networking, health checks
5. **k9s** lets you SEE everything running in the cluster

```
kind creates cluster ──▶ Terraform provisions resources on cluster
                              │
                              ├── Creates namespace (via K8s provider)
                              ├── Creates deployment, service, HPA (via K8s provider)
                              ├── Creates ingress (via K8s provider)
                              └── Installs monitoring (via Helm provider → calls Helm)
                                                          │
                                                    Helm renders
                                                    chart templates
                                                    into K8s YAML
                                                          │
                                                    K8s applies YAML
                                                    and runs pods
                                                          │
                                                    k9s visualizes
                                                    everything
```

### Why Not Just Use One Tool?

| Tool alone | Problem |
|------------|---------|
| Just K8s manifests | No templating, no state tracking, no drift detection |
| Just Helm | No infrastructure provisioning, no drift detection, can't manage non-app resources |
| Just Terraform | Can't package apps for sharing, HCL is verbose for K8s resources |

**Together they solve each other's gaps:**
- Terraform provides **drift detection** and **idempotency** (Helm and raw K8s lack this)
- Helm provides **packaging** and **versioning** (Terraform can call Helm releases)
- K8s provides the **runtime** — everything ultimately becomes K8s resources
- kind provides the **cluster** — no AWS account needed for local dev

---

## Prerequisites

| Tool | Version | Purpose | Install |
|------|---------|---------|---------|
| [Docker](https://docs.docker.com/get-docker/) | 20+ | Container runtime | System package |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.29+ | K8s CLI | `snap install kubectl` |
| [Helm](https://helm.sh/docs/intro/install/) | 3.14+ | K8s package manager | `snap install helm` |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start/) | 0.20+ | Local K8s cluster | [Install script](https://kind.sigs.k8s.io/docs/user/quick-start/#installing-from-release-binaries) |
| [Terraform](https://developer.hashicorp.com/terraform/install) | 1.5+ | Infrastructure as Code | [HashiCorp repo](https://developer.hashicorp.com/terraform/install) |
| [k9s](https://k9sro.io/) | 0.32+ | Terminal K8s dashboard | [Install](https://github.com/derailed/k9s#installation) |
| [Kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/) | 5+ | K8s manifest overlays (optional) | Built into kubectl |

Verify installations:

```bash
docker version --format '{{.Server.Version}}'
kubectl version --client --short 2>/dev/null || kubectl version --client
helm version --short
kind version
terraform version
k9s version
```

---

## Step 1: Create the kind Cluster

**kind** (Kubernetes IN Docker) creates a real K8s cluster on your laptop. It simulates what AWS EKS would give you in production.

Create `kind-config.yaml`:

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

**What just happened?**
- kind created 2 Docker containers: 1 control-plane (API server, etcd, scheduler) + 1 worker (kubelet, kube-proxy)
- Your `~/.kube/config` was updated with the cluster context `kind-omniflow`
- You now have a fully functional K8s cluster — same API as AWS EKS, just running locally

> **Note:** Port 80/443 host mappings are omitted because they may conflict with local services. Use `kubectl port-forward` instead.

---

## Step 2: Build and Load the Container Image

```bash
# Build the image
docker build -t ghcr.io/nkwatambe/omniflow-k8s-devops:local ./src

# Load it into the kind cluster nodes
kind load docker-image ghcr.io/nkwatambe/omniflow-k8s-devops:local --name omniflow
```

**What just happened?**
- Docker built the multi-stage image (Node.js build → nginx production)
- `kind load` copied the image into both the control-plane and worker Docker containers
- The image is now available inside the cluster without pulling from a registry

> **Why `:local` tag?** The Helm/Terraform configs reference `:dev` or `:latest` tags. For local dev, we use `:local` and patch the deployment to use `imagePullPolicy: Never`.

---

## Step 3: Deploy the Full System

### Recommended: Terraform + Helm Together

This is the **production-like** approach. Terraform provisions all infrastructure and calls Helm for the application:

```bash
cd terraform/environments/dev

# Initialize Terraform (downloads K8s + Helm providers)
terraform init

# Apply — creates namespace, deployment, service, HPA, network policy, ingress
terraform apply -auto-approve -var="kube_context=kind-omniflow"

# Patch for local image (Terraform creates :dev tag by default)
kubectl set image deployment/omniflow-frontend \
  omniflow-frontend=ghcr.io/nkwatambe/omniflow-k8s-devops:local \
  -n omniflow-dev
kubectl patch deployment omniflow-frontend -n omniflow-dev \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "Never"}]'
```

**What Terraform created (8 resources):**

| Resource | Module | What it is |
|----------|--------|------------|
| `kubernetes_namespace` | namespace | `omniflow-dev` namespace with labels |
| `kubernetes_service_account` | frontend | ServiceAccount for pod identity |
| `kubernetes_config_map` | frontend | Environment variables (NODE_ENV, etc.) |
| `kubernetes_deployment` | frontend | 1 pod running nginx with the app |
| `kubernetes_service` | frontend | ClusterIP service port 80 → pod port 8080 |
| `kubernetes_horizontal_pod_autoscaler_v2` | frontend | Scales 1-3 replicas based on CPU/memory |
| `kubernetes_network_policy` | frontend | Restricts ingress/egress traffic |
| `kubernetes_ingress_v1` | ingress | Routes traffic from omniflow.dev.local |

### Alternative: Helm Only

If you only need the application (no Terraform state management):

```bash
helm install omniflow-frontend ./helm/omniflow-frontend \
  --namespace omniflow-dev \
  --create-namespace \
  -f ./helm/omniflow-frontend/values-dev.yaml \
  --set image.tag=local \
  --set image.pullPolicy=Never \
  --set ingress.enabled=false
```

### Alternative: Raw K8s Manifests Only

For quick debugging or learning (no packaging, no state):

```bash
kubectl apply -f k8s/base/namespace.yaml
sleep 2
kubectl apply -f k8s/base/serviceaccount.yaml \
  -f k8s/base/configmap.yaml \
  -f k8s/base/deployment.yaml \
  -f k8s/base/service.yaml \
  -f k8s/base/hpa.yaml \
  -f k8s/base/networkpolicy.yaml

kubectl set image deployment/omniflow-frontend \
  omniflow-frontend=ghcr.io/nkwatambe/omniflow-k8s-devops:local -n omniflow
kubectl patch deployment omniflow-frontend -n omniflow \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "Never"}]'
```

---

## Step 4: Visualize Everything with k9s

[k9s](https://k9sro.io/) is a terminal UI for Kubernetes — like a task manager for your cluster. It shows you **everything** created by Terraform, Helm, or raw K8s manifests.

```bash
k9s --context kind-omniflow
```

### What to Look For in k9s

| k9s Shortcut | What it shows | Created by |
|-------------|---------------|------------|
| `0` (pods) | Running application pods | Terraform `frontend` module / Helm chart / K8s manifests |
| `1` (deployments) | Deployment with rollout status | Terraform `kubernetes_deployment` |
| `2` (services) | ClusterIP service mapping 80→8080 | Terraform `kubernetes_service` |
| `3` (configmaps) | Environment variables config | Terraform `kubernetes_config_map` |
| `4` (secrets) | TLS certs, credentials | Terraform `kubernetes_secret` (if configured) |
| `5` (ingresses) | HTTP routing rules | Terraform `kubernetes_ingress_v1` |
| `6` (network policies) | Traffic restrictions | Terraform `kubernetes_network_policy` |
| `7` (HPA) | Auto-scaling config | Terraform `kubernetes_horizontal_pod_autoscaler_v2` |
| `8` (service accounts) | Pod identity | Terraform `kubernetes_service_account` |
| `:ns` | All namespaces | Terraform `kubernetes_namespace` |
| `:helm` | Helm releases (if deployed via Helm) | Terraform `helm_release` / `helm install` |
| `:ctx` | K8s contexts (kind-omniflow) | kind |

### Useful k9s Commands

| Key | Action |
|-----|--------|
| `l` | View pod logs (follow mode) |
| `e` | Edit resource YAML |
| `d` | Describe resource |
| `s` | Shell into pod |
| `f` | Port-forward pod |
| `/` | Filter/search |
| `:po` | Switch to pods view |
| `:dp` | Switch to deployments view |
| `:svc` | Switch to services view |
| `:hpa` | Switch to HPA view |
| `:ing` | Switch to ingresses view |
| `:netpol` | Switch to network policies view |
| `Esc` | Back / quit |

### Verifying the Full System in k9s

1. Press `0` — you should see `omniflow-frontend` pod in `omniflow-dev` namespace, status `Running`
2. Select the pod, press `l` — you should see nginx access logs
3. Press `Esc`, then `:svc` — you should see `omniflow-frontend` service, port `80→8080`
4. Press `:hpa` — you should see autoscaler, targets `1-3 replicas`
5. Press `:netpol` — you should see network policy restricting traffic
6. Press `:ing` — you should see ingress for `omniflow.dev.local`

---

## Step 5: Verify the Deployment

### Check Pod Status

```bash
kubectl get pods -n omniflow-dev
# NAME                                 READY   STATUS    RESTARTS   AGE
# omniflow-frontend-xxxxxxxxxx-xxxxx   1/1     Running   0          60s
```

### Test the Health Endpoint

```bash
kubectl port-forward svc/omniflow-frontend -n omniflow-dev 3000:80
# In another terminal:
curl http://localhost:3000/health
# healthy
```

### Test the Application

```bash
curl http://localhost:3000/
# Returns HTML page with "Vite + React" heading
```

> **Port flow:** Browser:3000 → port-forward → Service:80 → Pod:8080 (nginx). Nginx listens on 8080 because the container runs as non-root user (UID 1001) which cannot bind to privileged ports (< 1024).

---

## Step 6: Access the Application

**Via port-forward (recommended for kind):**

```bash
kubectl port-forward svc/omniflow-frontend -n omniflow-dev 3000:80
```

Open http://localhost:3000

---

## Terraform Module Structure

```
terraform/
├── modules/
│   ├── namespace/        # K8s namespace with labels
│   ├── frontend/         # Deployment, Service, HPA, NetworkPolicy, ConfigMap, SA
│   ├── ingress/          # Ingress with TLS and annotations
│   └── monitoring/       # Prometheus/Grafana via Helm release
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

Terraform guarantees running `apply` multiple times produces the same result:

```bash
terraform apply -auto-approve -var="kube_context=kind-omniflow"
terraform plan -var="kube_context=kind-omniflow"  # Should show "No changes"
terraform apply -auto-approve -var="kube_context=kind-omniflow"  # No changes applied
```

### Drift Detection

If someone manually edits a K8s resource (e.g., changes replicas via kubectl), Terraform detects it:

```bash
# Simulate drift
kubectl scale deployment omniflow-frontend -n omniflow-dev --replicas=5

# Terraform detects the drift
terraform plan -var="kube_context=kind-omniflow"
# ~ kubernetes_deployment.frontend: replicas: "5" → "1"

# Re-converge to declared state
terraform apply -auto-approve -var="kube_context=kind-omniflow"
# replicas restored to 1
```

---

## Scaling

### Manual Scaling

```bash
kubectl scale deployment omniflow-frontend -n omniflow-dev --replicas=5
```

### Generate Load to Test HPA

```bash
kubectl run load-generator --image=busybox --restart=Never -n omniflow-dev -- \
  /bin/sh -c "while true; do wget -q -O- http://omniflow-frontend:80; done"
```

Watch in k9s: `:hpa` — you'll see replicas scale from 1 → 3.

Clean up:

```bash
kubectl delete pod load-generator -n omniflow-dev
```

---

## Update the Deployment

### Rolling Update

```bash
# Build a new image
docker build -t ghcr.io/nkwatambe/omniflow-k8s-devops:local ./src
kind load docker-image ghcr.io/nkwatambe/omniflow-k8s-devops:local --name omniflow

# Restart pods to pick up the new image
kubectl rollout restart deployment/omniflow-frontend -n omniflow-dev
```

Watch the rollout in k9s: `0` (pods view) — you'll see a new pod start, old pod terminate.

### Rollback

```bash
kubectl rollout history deployment/omniflow-frontend -n omniflow-dev
kubectl rollout undo deployment/omniflow-frontend -n omniflow-dev
```

---

## Troubleshooting

### Pod CrashLoopBackOff — Permission Denied on Port 80

**Symptom:** `bind() to 0.0.0.0:80 failed (13: Permission denied)`

**Cause:** Container runs as non-root (UID 1001). Linux prevents binding to ports < 1024.

**Fix:** nginx.conf uses `listen 8080`, Dockerfile has `EXPOSE 8080`, Service maps 80→8080.

### Pod ImagePullBackOff

```bash
kind load docker-image ghcr.io/nkwatambe/omniflow-k8s-devops:local --name omniflow
kubectl patch deployment omniflow-frontend -n omniflow-dev \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "Never"}]'
```

### Ingress Not Working

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s
```

---

## Clean Up

### Delete Application

```bash
# Terraform (removes everything it created)
cd terraform/environments/dev
terraform destroy -auto-approve -var="kube_context=kind-omniflow"

# Or Helm
helm uninstall omniflow-frontend --namespace omniflow-dev

# Or kubectl
kubectl delete namespace omniflow-dev
```

### Delete Cluster

```bash
kind delete cluster --name omniflow
```

---

## Architecture Diagram

```
                    ┌──────────────────────────────────────────────┐
                    │           kind K8s Cluster                    │
                    │        (simulates AWS EKS locally)            │
                    │                                              │
  Terraform ──────▶│  omniflow-dev namespace                      │
  provisions:      │    │                                         │
  - namespace       │    ├── Deployment (1 pod, containerPort 8080)│
  - configmap       │    ├── Service (ClusterIP:80 → :8080)       │
  - deployment      │    ├── HPA (1-3 replicas, CPU 70%)          │
  - service         │    ├── NetworkPolicy (restrict traffic)     │
  - HPA             │    ├── Ingress (omniflow.dev.local)         │
  - networkpolicy   │    └── ConfigMap (NODE_ENV=development)     │
  - ingress         │                                              │
  - serviceaccount  │  monitoring namespace (prod only)           │
                    │    └── Prometheus + Grafana (via Helm)       │
                    │                                              │
                    │  Control plane: API server, etcd, scheduler │
                    │  Worker: kubelet, kube-proxy, kindnet       │
                    └──────────────────────────────────────────────┘

  Port flow:  Browser:3000 → port-forward → Service:80 → Pod:8080 (nginx)

  Tool chain: kind (cluster) → Terraform (provision) → Helm (package) → K8s (run) → k9s (observe)
```
