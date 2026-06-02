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
| **Kustomize** | Manifest overlay engine | Inheritance for YAML | Patches base manifests per environment without duplicating files |

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
| Just Kustomize | No state tracking, no packaging into releases, no drift detection |

**Together they solve each other's gaps:**
- Terraform provides **drift detection** and **idempotency** (Helm and raw K8s lack this)
- Helm provides **packaging** and **versioning** (Terraform can call Helm releases)
- Kustomize provides **environment overlays** without duplicating manifests
- K8s provides the **runtime** — everything ultimately becomes K8s resources
- kind provides the **cluster** — no AWS account needed for local dev

---

## Three Deployment Paths: How They Relate

This project provides **three parallel ways** to deploy the same application, all producing functionally equivalent K8s resources:

| Path | Tool | State | Used by | `managed-by` label |
|------|------|-------|---------|-------------------|
| **A: Terraform modules** | `terraform apply` | `.tfstate` file | Local dev, drift detection | `"terraform"` |
| **B: Helm chart** | `helm upgrade --install` | Helm release secrets in K8s | CI/CD pipeline | `"Helm"` |
| **C: Kustomize overlays** | `kubectl apply -k` | None (dry) | Quick debugging, learning | `"kubectl"` |

**Do not mix paths in the same namespace.** Each tool tracks ownership differently. If Terraform created a Deployment and you then `helm install` over it, both tools think they own it and will fight.

### When to Use Which Path

| Scenario | Use | Why |
|----------|-----|-----|
| Local dev with drift detection | Terraform | `terraform plan` shows exactly what changed |
| CI/CD automated deployment | Helm | `helm upgrade --install` is idempotent, `--wait` blocks until ready |
| Quick test, throwaway | Kustomize | No state to clean up, just `kubectl delete namespace` |
| Adding monitoring stack | Terraform `helm_release` | Terraform manages the Helm release lifecycle alongside other infra |

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
- Docker built the multi-stage image (Node.js build stage → nginx production stage)
- `kind load` copied the image into both the control-plane and worker Docker containers
- The image is now available inside the cluster without pulling from a registry

> **Why `:local` tag?** The Helm/Terraform configs reference `:dev` or `:latest` tags. For local dev, we use `:local` and patch the deployment to use `imagePullPolicy: Never`. In CI/CD, the image is pushed to ghcr.io with `:sha-abc1234`, so the tag matches the registry.

---

## Step 3: Deploy the Full System

### Recommended: Terraform + Helm Together

This is the **production-like** approach. Terraform provisions all infrastructure and calls Helm for the application.

> **Important:** You MUST be inside the `terraform/environments/dev/` directory. Terraform only reads `.tf` files in the current directory.

```bash
# Step into the dev environment directory (not the repo root!)
cd terraform/environments/dev

# Initialize Terraform (downloads K8s + Helm providers)
terraform init

# Apply — creates all 8 resources. Returns immediately (wait_for_rollout=false for local dev)
terraform apply -auto-approve -var="kube_context=kind-omniflow"

# Patch for local image (Terraform creates :dev tag, but kind has :local)
kubectl set image deployment/omniflow-frontend \
  omniflow-frontend=ghcr.io/nkwatambe/omniflow-k8s-devops:local \
  -n omniflow-dev
kubectl patch deployment omniflow-frontend -n omniflow-dev \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "Never"}]'
```

> **Why two steps?** Terraform creates the deployment with `image: :dev` (the registry tag). For local dev, the image is loaded into kind as `:local` with `imagePullPolicy: Never`. In production CI/CD, the image is pushed to ghcr.io as `:dev`/`:sha-xxx`, so no patch is needed — Terraform's image tag matches the registry.

> **If you get "already exists" errors:** Leftover resources from a previous partial deploy. Delete the namespace first: `kubectl delete namespace omniflow-dev --context kind-omniflow`, then re-run `terraform apply`.

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

### Alternative: Kustomize Overlays

For quick debugging or learning (no state):

```bash
kubectl apply -k k8s/overlays/dev/
kubectl set image deployment/omniflow-frontend \
  omniflow-frontend=ghcr.io/nkwatambe/omniflow-k8s-devops:local -n omniflow-dev
kubectl patch deployment omniflow-frontend -n omniflow-dev \
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

## Terraform Resources Deep Dive

This section explains every Terraform resource — what it does, why it exists, and what happens when you modify it. This is the core of the system.

### Module Structure

```
terraform/
├── modules/
│   ├── namespace/        # K8s namespace with labels
│   ├── frontend/         # Deployment, Service, HPA, NetworkPolicy, ConfigMap, SA, Secret
│   ├── ingress/          # Ingress with TLS and annotations
│   └── monitoring/       # Prometheus/Grafana via Helm release
└── environments/
    ├── dev/              # 1 replica, minimal resources, no TLS, no monitoring
    ├── staging/          # 2 replicas, moderate resources, TLS, no monitoring
    └── prod/             # 3 replicas, full resources, TLS, monitoring, cert-manager
```

Each environment directory is a Terraform **root module** that calls the same modules with different variable values. This ensures environment parity — the same codebase, different scale.

---

### Resource 1: `kubernetes_namespace` (namespace module)

**What it does:** Creates an isolated Kubernetes namespace. All other resources live inside this namespace. Namespaces prevent name collisions and enable resource quotas.

```hcl
resource "kubernetes_namespace" "this" {
  metadata {
    name   = var.namespace
    labels = merge(var.labels, { "app.kubernetes.io/part-of" = "omniflow-platform" })
  }
}
```

**Why it matters:** Without namespaces, every team's resources would collide in the default namespace. The `part-of=omniflow-platform` label is critical — the NetworkPolicy uses it to allow traffic between OmniFlow namespaces while blocking everything else.

**Modification effects:**
| Change | Effect |
|--------|--------|
| Change `name` | **Destroys and recreates** the namespace AND everything inside it. Destructive. |
| Add/remove `labels` | Updates in-place. Non-disruptive. The `part-of` label is used by NetworkPolicy selectors. |

---

### Resource 2: `kubernetes_config_map` (frontend module)

**What it does:** Stores non-sensitive configuration as key-value pairs. These values are injected into the container as environment variables via `envFrom`.

```hcl
resource "kubernetes_config_map" "frontend" {
  data = var.config  # e.g. { NODE_ENV = "development", VITE_APP_TITLE = "OmniFlow Dev" }
}
```

**Why it matters:** Separating config from the container image means the same image works across environments. You don't rebuild the Docker image for dev vs prod — you just change the ConfigMap.

**How it triggers rollouts:** The Deployment has an annotation:

```yaml
checksum/config: <sha256-hash-of-configmap-data>
```

When the ConfigMap data changes, the hash changes, which forces Kubernetes to perform a rolling update. This means **config changes are automatically picked up** without manual pod restarts.

**Modification effects:**
| Change | Effect |
|--------|--------|
| Change `NODE_ENV` | Triggers rolling update. Pod gets new env var. Affects React build behavior and error messages. |
| Change `NGINX_WORKER_PROCESSES` | Triggers rolling update. `"auto"` uses one worker per CPU core. Lowering to `"1"` saves memory but reduces concurrency. |
| Change `NGINX_WORKER_CONNECTIONS` | Triggers rolling update. `"1024"` means each worker handles 1024 simultaneous connections. Increase for high-traffic, decrease to save memory. |

---

### Resource 3: `kubernetes_secret` (frontend module, conditional)

**What it does:** Stores sensitive data (API keys, tokens) as Kubernetes Secrets. Only created when `var.secrets` is non-empty.

```hcl
count = length(var.secrets) > 0 ? 1 : 0
```

**Why it matters:** Secrets are stored base64-encoded in etcd (not plaintext like ConfigMaps). In production, you'd enable encryption at rest and use an external secrets manager (Vault, AWS Secrets Manager).

**Modification effects:**
| Change | Effect |
|--------|--------|
| Add secrets where none existed | Creates the Secret resource. Does **not** automatically trigger a rollout (no checksum annotation for secrets). |
| Remove all secrets | Destroys the Secret resource. Pods lose access to those env vars. |
| Change secret values | Updates the Secret. Does **not** automatically trigger a rollout — you must manually restart pods. |

> **Important difference from ConfigMap:** ConfigMap changes trigger automatic rollouts via the checksum annotation. Secret changes do NOT. This is intentional — secret values shouldn't appear in rollout annotations.

---

### Resource 4: `kubernetes_service_account` (frontend module)

**What it does:** Creates a dedicated identity for the frontend pods. Follows the **principle of least privilege**.

```hcl
resource "kubernetes_service_account" "frontend" {
  automount_service_account_token = false
}
```

**Why it matters:** By default, every pod gets a service account token mounted at `/var/run/secrets/kubernetes.io/serviceaccount`, which allows the pod to talk to the Kubernetes API. Setting `automount_service_account_token = false` means the frontend pod **cannot** access the K8s API. This prevents a compromised container from querying the cluster, listing secrets, or spawning pods.

**Modification effects:**
| Change | Effect |
|--------|--------|
| Set `automount_service_account_token = true` | Pod can now talk to the K8s API. Useful if the app needs to discover services dynamically, but increases attack surface. |
| Change the SA name | Requires recreating the Deployment (which references this SA). |

**When would you need the token?** If the frontend needed to call the K8s API (e.g., to discover backend services, read ConfigMaps dynamically, or report health to a custom operator). For a static nginx frontend, there is zero reason to have API access.

---

### Resource 5: `kubernetes_deployment` (frontend module) — The Core Workload

**What it does:** Deploys the frontend application as nginx-based pods. This is the most complex resource with the most tunable parameters.

#### Replicas

```hcl
replicas = var.replicas  # dev: 1, staging: 2, prod: 3
```

- **Increase:** More pods = higher availability and throughput. More resource consumption.
- **Decrease:** Fewer pods = lower cost, but less resilience. A single pod means a single point of failure.
- **With HPA enabled:** The HPA overrides this value. Replicas becomes the **initial** count, not a fixed floor. The HPA's `min_replicas` is the actual floor.

#### Rolling Update Strategy

```hcl
strategy {
  type = "RollingUpdate"
  rolling_update {
    max_surge       = 1   # At most 1 extra pod above desired count
    max_unavailable = 0   # Zero pods allowed to be unavailable
  }
}
```

- **`max_surge = 1`:** During a deployment, K8s creates 1 new pod first, waits for it to pass readiness, then terminates 1 old pod. This means you temporarily have `N+1` pods during rollout.
- **`max_unavailable = 0`:** Zero-downtime deployments. No pod is killed until its replacement is ready.
- **Increase `max_surge` to 3:** Faster rollouts (3 new pods at once), but uses more resources during deployment. Good for large deployments.
- **Increase `max_unavailable` to 1:** Faster rollouts but brief capacity reduction. Acceptable for non-critical apps.
- **Both at 0/0:** Not allowed — you'd deadlock. You need at least one of surge or unavailable.

#### Resource Requests and Limits

```hcl
resources {
  requests = { cpu = "25m", memory = "32Mi" }   # Guaranteed minimum
  limits   = { cpu = "100m", memory = "64Mi" }   # Hard ceiling
}
```

**Requests vs Limits explained:**
- **`requests`** = what the scheduler **guarantees** the pod gets. Used for scheduling decisions — K8s places pods on nodes that have at least this much unreserved capacity.
- **`limits`** = the **hard ceiling**. Exceed CPU limit = throttled. Exceed memory limit = OOM killed (pod dies).

| Change | Effect |
|--------|--------|
| Increase `requests.cpu` | Pod gets more guaranteed CPU. Better performance under contention. Harder to schedule (needs bigger node). |
| Decrease `requests.cpu` | Pod gets less guaranteed CPU. Under node pressure, this pod gets throttled first. Easier to schedule on small nodes. |
| Increase `limits.cpu` | Pod can burst more CPU when available. Doesn't affect scheduling (limits aren't considered for placement). |
| Decrease `limits.cpu` | Pod gets throttled sooner. If `limits.cpu < requests.cpu`, the pod is always throttled (misconfiguration). |
| Increase `requests.memory` | More memory guaranteed. Harder to schedule. Node needs more unreserved capacity. |
| Increase `limits.memory` | Pod can use more memory before OOM kill. Risk of node memory pressure if many pods burst simultaneously. |
| Decrease `limits.memory` | Pod OOM-killed sooner. If the app uses more than the limit, it crashes repeatedly. |

**Why dev uses 25m/32Mi while prod uses 100m/128Mi:**
- Dev runs 1 pod on a local kind cluster (limited resources). Small values ensure the pod fits.
- Prod runs 3+ pods on real nodes. Larger values ensure responsive performance under load.
- Setting dev requests too high would cause `Pending` pods on resource-constrained kind clusters.
- Setting prod limits too low would cause OOM kills or CPU throttling under real traffic.

#### Health Probes

```hcl
liveness_probe {   # "Is the app alive?" → restarts pod if dead
  http_get { path = "/health", port = "http" }
  initial_delay_seconds = 5
  period_seconds        = 30
  failure_threshold     = 3
}
readiness_probe {  # "Is the app ready to serve?" → removes from Service if not
  http_get { path = "/health", port = "http" }
  initial_delay_seconds = 3
  period_seconds        = 10
  failure_threshold     = 3
}
startup_probe {    # "Did the app start?" → gives time for slow startup
  http_get { path = "/health", port = "http" }
  period_seconds        = 5
  failure_threshold     = 12   # 5s × 12 = 60s max startup time
}
```

**Three probes, three jobs:**

| Probe | Failure action | Period | Purpose |
|-------|---------------|--------|---------|
| **Startup** | Kill container | Every 5s | Gives slow apps up to 60s to start. Liveness/readiness don't run until startup passes. |
| **Liveness** | Restart pod | Every 30s | Catches deadlocks, infinite loops, corrupted state. Restart = fresh pod. |
| **Readiness** | Remove from Service | Every 10s | Catches "alive but can't serve" state (loading cache, waiting for DB). Pod stays running but gets no traffic. |

**Modification effects:**
| Change | Effect |
|--------|--------|
| Increase `failure_threshold` | More tolerant of temporary glitches. Slower to react to real failures. |
| Decrease `failure_threshold` | Faster detection of real failures. More false positives (pod restarted unnecessarily). |
| Increase `period_seconds` | Less frequent checks = less overhead. Slower failure detection. |
| Decrease `period_seconds` | Faster detection. More HTTP requests to the pod. |
| Remove startup probe | Liveness probe kicks in immediately. If the app takes >5s + 3×30s to start, liveness kills it → CrashLoopBackOff. |

#### Security Context

```hcl
security_context {
  run_as_non_root              = true     # Pod MUST run as non-root
  run_as_user                  = 1001     # UID
  run_as_group                 = 1001     # GID
  fs_group                     = 1001     # Filesystem group for volumes
  seccomp_profile_type         = "RuntimeDefault"
}

container_security_context {
  allow_privilege_escalation   = false    # No setuid/setgid
  read_only_root_filesystem    = true     # Root FS is immutable
  capabilities_drop            = ["ALL"]  # Remove all Linux capabilities
}
```

**Why each setting matters:**

| Setting | What it prevents | Why you'd relax it |
|---------|-----------------|-------------------|
| `run_as_non_root` | Container can't escalate to root | Never relax this for production |
| `read_only_root_filesystem` | Attacker can't write malicious files to root FS | Needed if app writes to `/` (nginx needs `/tmp`, `/var/cache/nginx`, `/var/run` → provided as `emptyDir` volumes) |
| `capabilities_drop: ALL` | Removes all Linux capabilities (e.g., `NET_ADMIN`, `SYS_ADMIN`) | Only relax if app needs raw socket access or system calls |
| `allow_privilege_escalation: false` | Prevents `setuid` binaries from granting root | Never relax this |
| `seccomp_profile: RuntimeDefault` | Restricts system calls to a known-safe subset | Only relax for specialized workloads (debuggers, profilers) |

**Why three `emptyDir` volumes:** nginx needs writable directories even though root FS is read-only. The `empty_dir` volumes (`/tmp`, `/var/cache/nginx`, `/var/run`) are writable but ephemeral — their data is lost when the pod restarts.

#### Topology Spread Constraints

```hcl
topology_spread_constraint {
  max_skew           = 1
  topology_key       = "kubernetes.io/hostname"
  when_unsatisfiable = "DoNotSchedule"
}
```

**What it does:** Forces pods to spread across different physical nodes. If you have 3 pods and 3 nodes, each node gets 1 pod.

**Why it matters:** If all pods land on the same node and that node dies, you lose 100% of capacity. Spread ensures a single node failure only kills a fraction of pods.

| Change | Effect |
|--------|--------|
| `max_skew = 1` (current) | At most 1 pod difference between any two nodes. Balanced. |
| `max_skew = 2` | More skewed placement allowed. Easier scheduling on small clusters. |
| `when_unsatisfiable = DoNotSchedule` | Pod stays Pending if it can't meet the constraint. Prefers balance over running. |
| `when_unsatisfiable = ScheduleAnyway` | Always schedules the pod, even if unbalanced. Prefers running over balance. |
| **Disabled (dev)** | Dev runs on a single kind node, so spread is impossible. Disabling avoids Pending pods. |

#### `wait_for_rollout`

```hcl
wait_for_rollout = var.wait_for_rollout  # dev: false, staging/prod: true
```

**Why dev sets this to `false`:** In local dev, Terraform creates the Deployment with `image: :dev`, but the image doesn't exist in kind (you loaded it as `:local`). If `wait_for_rollout = true`, Terraform would block forever waiting for a pod that can never start. Setting `false` lets Terraform return immediately, then you patch the image tag.

**Why staging/prod keep `true`:** In real environments, the image exists in the registry. Terraform should confirm the rollout succeeds before moving on (e.g., before creating the Ingress that points to the Deployment).

---

### Resource 6: `kubernetes_service` (frontend module)

**What it does:** Creates a stable network endpoint (ClusterIP) that routes traffic to pods. Pods come and go (new IP each time), but the Service IP never changes.

```hcl
resource "kubernetes_service" "frontend" {
  spec {
    type = "ClusterIP"    # Only reachable from within the cluster
    port { port = 80, target_port = "http" }  # 80 → 8080
    selector = local.selector_labels
  }
}
```

**How Service → Pod routing works:**
1. Service watches for pods matching `selector` labels (`app.kubernetes.io/name: omniflow-frontend`)
2. When a pod's readiness probe passes, the Service adds the pod's IP to its endpoint list
3. Traffic to `ServiceIP:80` is load-balanced across all ready pod IPs on port 8080
4. When a pod's readiness probe fails, the Service removes it from the endpoint list (no traffic sent)

**Why `ClusterIP` and not `LoadBalancer`:**
- `ClusterIP`: Internal only. Ingress forwards external traffic to this Service. This is the standard pattern.
- `NodePort`: Exposes on a high port on every node. Bypasses Ingress. Useful for debugging.
- `LoadBalancer`: Creates a cloud load balancer (AWS ELB, GCP LB). Costs money. Only works in cloud clusters.

**Port mapping (80 → 8080):**
- Service port 80 is the **conventional HTTP port** — other services and Ingress expect this.
- Container port 8080 is because **non-root users can't bind to port 80** (< 1024 requires root).
- The Service bridges this gap transparently.

**Modification effects:**
| Change | Effect |
|--------|--------|
| Change to `NodePort` | Service reachable from outside the cluster on a port 30000-32767. Useful for debugging without Ingress. |
| Change to `LoadBalancer` | Creates a cloud load balancer. Bypasses Ingress. Only works on cloud clusters (AWS/GCP/Azure). |
| Change port from 80 | The Ingress targets port 80, so it would break. Must update Ingress too. |

---

### Resource 7: `kubernetes_horizontal_pod_autoscaler_v2` (frontend module, conditional)

**What it does:** Automatically adjusts the number of pod replicas based on CPU and memory utilization. Only created when `var.hpa_enabled = true`.

```hcl
resource "kubernetes_horizontal_pod_autoscaler_v2" "frontend" {
  count = var.hpa_enabled ? 1 : 0

  spec {
    min_replicas = var.hpa_min_replicas   # dev: 1, staging: 2, prod: 3
    max_replicas = var.hpa_max_replicas   # dev: 3, staging: 5, prod: 10

    metric {
      type = "Resource"
      resource { name = "cpu", target { type = "Utilization", average_utilization = 70 } }
    }
    metric {
      type = "Resource"
      resource { name = "memory", target { type = "Utilization", average_utilization = 80 } }
    }
  }
}
```

**How HPA works step by step:**
1. Every 15 seconds, the metrics server collects CPU/memory usage from all pods
2. HPA calculates: `desired_replicas = ceil(current_replicas × (current_utilization / target_utilization))`
3. Example: 3 pods at 90% CPU with target 70% → `ceil(3 × 90/70) = ceil(3.86) = 4 pods`
4. HPA tells the Deployment to scale to 4 replicas
5. New pod starts, traffic redistributes, CPU per pod drops

**Scale-up/down behavior:**

| Direction | Stabilization window | Policy | Reason |
|-----------|---------------------|--------|--------|
| **Scale up** | 60s | `Max` (most aggressive) + 100%/60s | React quickly to load spikes. Can double pod count every 60s. |
| **Scale down** | 300s (5 min) | `Min` (most conservative) + 10%/60s | Don't thrash. Wait 5 minutes before scaling down. Remove only 10% at a time. |

**Why the asymmetry:** Scaling up is urgent (users are experiencing latency). Scaling down is not (extra pods just cost money, don't break anything). Quick scale-up + slow scale-down prevents "flapping" (oscillating between N and N+1 pods).

**Modification effects:**
| Change | Effect |
|--------|--------|
| Increase `max_replicas` | Higher ceiling = handles bigger traffic spikes. More cost when spike occurs. |
| Decrease `max_replicas` | Caps scaling. Saves money. Risk of overload if traffic exceeds capacity of max pods. |
| Increase `min_replicas` | Higher baseline = always ready for traffic. Higher minimum cost. |
| Decrease `min_replicas` | Lower baseline cost. Risk: if traffic spikes, HPA needs time to start new pods (30-60s cold start). |
| Decrease `target_cpu` from 70% to 50% | Scales earlier (more aggressive). More pods, lower latency under load, higher cost. |
| Increase `target_cpu` from 70% to 90% | Scales later (more conservative). Fewer pods, risk of saturation before scaling kicks in. |
| Disable HPA | Pods stay at static `replicas` count. No auto-scaling. Manual scaling only. |

**Why dev uses max 3 vs prod max 10:**
- Dev runs on a 1-node kind cluster with ~4GB RAM. Scaling beyond 3 pods would exhaust resources.
- Prod runs on multi-node clusters with auto-scaling node groups. 10 pods is a reasonable ceiling.

---

### Resource 8: `kubernetes_network_policy` (frontend module, conditional)

**What it does:** Enforces network-level firewall rules for the frontend pods. Only created when `var.network_policy_enabled = true`. Requires a CNI plugin that supports NetworkPolicy (Calico, Cilium — NOT Flannel).

```
                     NetworkPolicy Rules
                    ┌─────────────────────┐
                    │  Frontend Pods       │
                    │                      │
  Ingress allowed:  │  ← omniflow-platform │  (same app, different namespace)
  Ingress allowed:  │  ← ingress-nginx     │  (the Ingress controller)
                    │                      │
  Egress allowed:   │  → kube-system:53    │  (DNS only)
                    │  → (nothing else)    │
                    └─────────────────────┘
```

**Ingress rules (who can reach the frontend):**
| Allowed from | Port | Why |
|-------------|------|-----|
| Namespaces with label `app.kubernetes.io/part-of: omniflow-platform` | TCP 80 | Other OmniFlow services (backend API, admin UI) in other namespaces |
| Pods with label `app.kubernetes.io/name: ingress-nginx` | TCP 80 | The nginx Ingress controller that routes external traffic to the Service |

**Egress rules (what the frontend can reach):**
| Allowed to | Port | Why |
|-----------|------|-----|
| Namespaces with label `app.kubernetes.io/name: kube-system` | TCP/UDP 53 | DNS resolution (pods must resolve service names like `omniflow-frontend:80`) |

**Important:** The egress only allows DNS. The frontend **cannot** reach any external APIs or backend services. If the frontend needs to call backend APIs, additional egress rules must be added.

**Modification effects:**
| Change | Effect |
|--------|--------|
| Disable NetworkPolicy | All traffic is allowed in/out. Less secure, but no risk of blocking legitimate traffic. Useful for debugging. |
| Add egress for backend API | `egress { to [{ namespace_selector { match_labels = { "app.kubernetes.io/part-of" = "omniflow-platform" } } }], ports [{ port = 8080, protocol = "TCP" }] }` — allows frontend to reach backend services. |
| Add egress for external APIs | `egress { to [{ ip_block { cidr = "0.0.0.0/0" except = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] } }], ports [{ port = 443, protocol = "TCP" }] }` — allows HTTPS to internet but blocks internal network. |
| Remove ingress from ingress-nginx | Ingress controller can't reach frontend. External traffic breaks. |

**Why NetworkPolicy matters even in dev:** It catches misconfigurations early. If your app works in dev with NetworkPolicy, it will work in prod. If you only test without NetworkPolicy, you might discover egress issues in prod when it's too late.

---

### Resource 9: `kubernetes_ingress_v1` (ingress module)

**What it does:** Exposes the frontend Service to external HTTP/HTTPS traffic via an nginx Ingress controller. Maps a domain name to the Service.

```hcl
resource "kubernetes_ingress_v1" "frontend" {
  spec {
    ingress_class_name = "nginx"
    rule {
      host = var.host   # dev: omniflow.dev.local, prod: omniflow.example.com
      http {
        path { path = "/", path_type = "Prefix", backend { service { name = var.service_name, port { number = 80 } } } }
      }
    }
    tls { hosts = [var.host], secret_name = "${var.app_name}-tls" }  # conditional
  }
}
```

**How traffic flows through Ingress:**
```
Browser → DNS resolves omniflow.example.com → Ingress Controller (nginx)
  → Ingress rule matches host → routes to Service:80 → Pod:8080
```

**Key annotations:**

| Annotation | Value | Purpose |
|-----------|-------|---------|
| `ssl-redirect` | `"true"` | HTTP requests → redirect to HTTPS |
| `force-ssl-redirect` | `"true"` | Forces redirect even if backend isn't TLS |
| `proxy-body-size` | `"10m"` | Max request body 10MB (prevents oversized uploads) |
| `cert-manager.io/cluster-issuer` | `"letsencrypt-prod"` | Auto-provisions TLS certs via Let's Encrypt (prod only) |

**TLS across environments:**

| Environment | TLS | Why |
|-------------|-----|-----|
| **Dev** | Off (`tls_enabled = false`) | No real domain, no cert-manager. Ingress works on HTTP only. |
| **Staging** | On (self-signed or manual cert) | Tests TLS configuration before prod. Uses `omniflow-staging-tls` secret. |
| **Prod** | On + cert-manager + Let's Encrypt | Automatic certificate provisioning and renewal. Uses `letsencrypt-prod` issuer. |

**Modification effects:**
| Change | Effect |
|--------|--------|
| Change `host` | Frontend responds on new domain. Old domain stops routing. DNS must be updated. |
| Disable TLS in prod | All traffic is plaintext. Security violation. |
| Increase `proxy-body-size` | Allows larger file uploads. Risk of DoS via large payloads. |
| Add additional path rules | Can route `/api` to a different Service (backend API). Enables multiple services behind one domain. |

---

### Resource 10: `helm_release` (monitoring module, prod only)

**What it does:** Deploys the full `kube-prometheus-stack` Helm chart, which installs Prometheus, Grafana, Alertmanager, Node Exporter, and kube-state-metrics.

```hcl
resource "helm_release" "prometheus_stack" {
  name       = "monitoring"
  chart      = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  version    = "58.0.0"
  namespace  = "monitoring"
}
```

**Why monitoring is prod-only:**
- Monitoring stack consumes significant resources (~500m CPU, ~2Gi RAM for Prometheus alone)
- Dev/staging don't need 30-day metric retention or alerting
- The frontend has `prometheus.io/scrape: "true"` annotations, so Prometheus auto-discovers and scrapes `/health` on port 80

**Key configuration:**

| Parameter | Default | What it controls |
|-----------|---------|-----------------|
| `retention` | 10d (prod: 30d) | How long Prometheus stores historical data. Longer = more disk, better trend analysis. |
| `storage_size` | 10Gi (prod: 50Gi) | PVC size for Prometheus. Running out = Prometheus crashes. |
| `grafana.persistence.enabled` | false | If false, Grafana dashboards are lost on pod restart. Should be true in prod. |
| `grafana.adminPassword` | "admin" | Default password. **Must be overridden in prod**. |

**Modification effects:**
| Change | Effect |
|--------|--------|
| Increase `retention` from 30d to 90d | Stores 3 months of data. Needs more disk (~3x). Better for capacity planning. |
| Decrease `retention` to 7d | Less disk. Loses historical context faster. May miss slow trends. |
| Increase `storage_size` | Gives Prometheus more room. No immediate effect, but prevents future disk-full crashes. |
| Decrease `storage_size` | Risk of Prometheus crashing when disk fills. Data loss. |
| Enable Grafana persistence | Dashboards survive pod restarts. Requires a StorageClass that supports PVC. |
| Increase Prometheus CPU/memory requests | Better query performance on large datasets. Handles more scrape targets. |
| Decrease Prometheus CPU/memory requests | May OOM-kill under heavy scrape/query load. |

---

### How Terraform Modules Connect

```
environments/dev/main.tf
  │
  ├── module "namespace"  ──→ creates kubernetes_namespace (omniflow-dev)
  │                              │
  │                              │ outputs: namespace_name
  │                              ▼
  ├── module "frontend"   ──→ receives namespace_name
  │                              │
  │                              ├── creates ConfigMap, Secret, ServiceAccount
  │                              ├── creates Deployment (references ConfigMap, SA)
  │                              ├── creates Service (selector matches Deployment labels)
  │                              ├── creates HPA (targets Deployment)
  │                              └── creates NetworkPolicy (selector matches Deployment labels)
  │                              │
  │                              │ outputs: service_name, namespace
  │                              ▼
  ├── module "ingress"    ──→ receives service_name, namespace
  │                              │
  │                              └── creates Ingress (routes to Service)
  │
  └── (no monitoring module in dev)

environments/prod/main.tf
  │
  ├── module "namespace"
  ├── module "frontend"
  ├── module "ingress"
  └── module "monitoring"  ──→ creates helm_release (kube-prometheus-stack)
```

Every module depends on the outputs of the previous one. Terraform's dependency graph ensures resources are created in the correct order: namespace first, then frontend resources, then ingress, then monitoring.

---

## Environment Deep Dive

### Why Three Environments?

| | Dev | Staging | Prod |
|---|---|---|---|
| **Purpose** | Developer iteration speed | Pre-release validation | User-facing production |
| **Who uses it** | Developers | QA, product | End users |
| **Failure impact** | Nobody cares | Team notices | Revenue/reputation loss |
| **Cost** | Minimal | Moderate | Full |

### Complete Configuration Comparison

| Setting | Dev | Staging | Prod | Why it scales this way |
|---------|-----|---------|------|----------------------|
| **Replicas** | 1 | 2 | 3 | 1 = cheapest; 2 = can survive 1 failure; 3 = minimum for rolling updates with zero downtime |
| **CPU request** | 25m | 50m | 100m | 25m = 2.5% of a core. Enough for nginx serving static files with no traffic. 100m = guaranteed 10% of a core for real traffic. |
| **CPU limit** | 100m | 200m | 500m | Static files are cheap. 100m handles dev. 500m allows burst during traffic spikes in prod. |
| **Memory request** | 32Mi | 64Mi | 128Mi | nginx + React static files use ~20-30MB. 32Mi fits. 128Mi gives headroom for caching in prod. |
| **Memory limit** | 64Mi | 128Mi | 256Mi | Hard ceiling. 64Mi is tight (OOM if nginx caches aggressively). 256Mi is safe for prod workloads. |
| **HPA min** | 1 | 2 | 3 | Matches replicas. Ensures baseline availability. |
| **HPA max** | 3 | 5 | 10 | Kind cluster can't fit >3 pods. Prod has capacity for 10. |
| **HPA target CPU** | 70% | 70% | 70% | Same across all — 70% is the standard trigger point. Below 70% = comfortable. Above = scale up. |
| **Topology spread** | Off | On | On | Dev has 1 node (spread impossible). Staging/prod have multi-node clusters. |
| **Wait for rollout** | Off | On | On | Dev: image doesn't exist yet (patched after). Staging/prod: image in registry, wait for confirmation. |
| **TLS** | Off | On | On + cert-manager | Dev has no real domain. Staging tests TLS config. Prod uses automatic Let's Encrypt certs. |
| **Ingress host** | `omniflow.dev.local` | `omniflow.staging.local` | `omniflow.example.com` | Different domains per environment. `.local` = not real DNS, only for testing. |
| **Monitoring** | Off | Off | On | Monitoring is expensive (500m+ CPU, 2Gi+ RAM). Not needed in dev/staging. |
| **Prometheus retention** | N/A | N/A | 30d | 30 days is standard for prod. Allows month-over-month comparisons. |
| **Prometheus storage** | N/A | N/A | 50Gi | 30d of metrics from a medium cluster ≈ 30-50GB. |

### The Scaling Logic

Resource allocation scales roughly **linearly** across environments:

```
Dev    = 1× baseline  (1 replica, 25m/32Mi)
Staging = 2× baseline  (2 replicas, 50m/64Mi)
Prod   = 4× baseline  (3 replicas, 100m/128Mi) + monitoring overhead
```

This is intentional. You don't want dev to be so different from prod that bugs only appear in production. Environment parity means the same code runs the same way — just smaller.

### What NOT to Change Across Environments

Some settings are **identical** across all environments because they're security/reliability fundamentals, not tunable parameters:

| Setting | Same in all envs | Why |
|---------|-----------------|-----|
| Security context (non-root, read-only FS, drop ALL) | Yes | Security is not optional in any environment |
| Rolling update strategy (maxSurge=1, maxUnavailable=0) | Yes | Zero-downtime deployment is always the goal |
| Health probes (paths, thresholds) | Yes | If it's healthy in dev, it should be healthy in prod |
| Service type (ClusterIP) | Yes | Always route through Ingress |
| Network policy | Yes | Security boundaries don't change by environment |
| ServiceAccount automount = false | Yes | Least privilege is always correct |

---

## How Helm Fits In

### The Helm Chart: A Parallel Implementation

The Helm chart at `helm/omniflow-frontend/` is a **parallel deployment path** that creates the same K8s resources as the Terraform modules. It's used by the CI/CD pipeline.

```
Helm chart templates → rendered YAML → kubectl apply → K8s resources
                    ↑
        values.yaml (defaults)
        values-dev.yaml (overlays)
        --set flags (CI/CD overrides)
```

### How Helm Values Merge (Priority Low → High)

1. **`values.yaml`** — chart defaults (replicaCount: 3, security hardening, probes, etc.)
2. **`values-dev.yaml`** — environment overlay (replicaCount: 1, lower resources)
3. **`--set image.tag=sha-abc1234`** — CLI override (highest priority, used by CI/CD)

Example merge for dev deployment:
```
values.yaml:           replicaCount=3, resources.requests.cpu="50m"
  ↓ merge with
values-dev.yaml:       replicaCount=1, resources.requests.cpu="25m"
  ↓ merge with
--set image.tag=local: image.tag="local"
  ↓ result
Final:                 replicaCount=1, resources.requests.cpu="25m", image.tag="local"
```

### Helm Chart Templates and What They Create

| Template | K8s Resource | Key Values Used |
|----------|-------------|-----------------|
| `_helpers.tpl` | (reusable named templates) | Labels, selector labels, names |
| `deployment.yaml` | Deployment | `.Values.replicaCount`, `.Values.image`, `.Values.resources`, `.Values.securityContext` |
| `service.yaml` | Service (ClusterIP) | `.Values.service.type`, `.Values.service.port` |
| `ingress.yaml` | Ingress | `.Values.ingress.enabled`, `.Values.ingress.hosts`, `.Values.ingress.tls` |
| `configmap.yaml` | ConfigMap | `.Values.config` |
| `serviceaccount.yaml` | ServiceAccount | `.Values.serviceAccount.create`, `.Values.serviceAccount.automountServiceAccountToken` |
| `hpa.yaml` | HorizontalPodAutoscaler | `.Values.autoscaling.enabled`, `.Values.autoscaling.minReplicas`, `.Values.autoscaling.maxReplicas` |
| `networkpolicy.yaml` | NetworkPolicy | `.Values.networkPolicy.enabled` |

### How CI/CD Uses Helm

The GitHub Actions pipeline (`.github/workflows/ci.yml`) uses `helm upgrade --install`:

```yaml
helm upgrade --install omniflow-frontend ./helm/omniflow-frontend \
  --namespace omniflow-staging \
  --create-namespace \
  -f ./helm/omniflow-frontend/values-staging.yaml \
  --set image.tag=sha-${{ needs.build.outputs.image_tag }} \
  --wait \
  --timeout 300s
```

**Key points:**
- `upgrade --install` is idempotent: installs if new, upgrades if existing
- `--set image.tag=sha-xxx` pins the exact image from the build step
- `--wait` blocks until all pods are ready (up to 300s)
- Helm creates a **release** — a versioned snapshot that can be rolled back with `helm rollback`

### Terraform `helm_release` vs Direct `helm install`

| | Terraform `helm_release` | Direct `helm install` |
|---|---|---|
| **Used for** | Monitoring stack (prometheus) | Frontend app (CI/CD) |
| **State** | Managed in `.tfstate` | Managed in K8s secrets |
| **Drift detection** | Yes (`terraform plan` shows changes) | No (`helm diff` plugin optional) |
| **Rollback** | `terraform apply` with previous values | `helm rollback` |
| **Why both?** | Monitoring is infrastructure → Terraform manages it | Frontend is an app → CI/CD deploys it via Helm |

---

## How Kustomize Fits In

### Base Manifests + Environment Overlays

```
k8s/base/            → 8 static YAML files (namespace, deployment, service, etc.)
k8s/overlays/dev/    → JSON patches: lower resources, 1 replica, dev tag
k8s/overlays/staging/ → JSON patches: medium resources, 2 replicas, staging tag
k8s/overlays/prod/   → JSON patches: high resources, 3 replicas, latest tag
```

Kustomize uses **JSON Patch (RFC 6902)** to surgically modify specific fields:

```yaml
# k8s/overlays/dev/kustomization.yaml
patches:
  - target:
      kind: Deployment
      name: omniflow-frontend
    patch:
      - op: replace
        path: /spec/replicas
        value: 1
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/cpu
        value: 25m
```

**What Kustomize does NOT patch** (inherited unchanged from base):
- Security context (non-root, read-only FS, dropped capabilities)
- Probe definitions
- Service type (ClusterIP)
- NetworkPolicy rules
- Deployment strategy (RollingUpdate)

### When to Use Kustomize vs Helm vs Terraform

| Need | Tool | Why |
|------|------|-----|
| Simple environment-specific patches | Kustomize | No templating, no state, just patches |
| Reusable package with versioning | Helm | Chart can be shared, versioned, published |
| Full infra management with drift detection | Terraform | State tracking, plan/apply lifecycle |

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

### Idempotency

Terraform guarantees running `apply` multiple times produces the same result:

```bash
terraform apply -auto-approve -var="kube_context=kind-omniflow"
terraform plan -var="kube_context=kind-omniflow"  # Should show "No changes"
terraform apply -auto-approve -var="kube_context=kind-omniflow"  # No changes applied
```

This is different from `kubectl apply` which is "last write wins" with no state tracking. If you `kubectl apply` the same manifest twice, the second one is a no-op. But if someone changed the resource in between, `kubectl apply` silently overwrites their changes. Terraform would **detect the drift** and show you exactly what changed.

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

**Why this matters in production:** Without drift detection, someone could `kubectl edit` a deployment, change security settings, and nobody would know. Terraform's `plan` catches any deviation from the declared state.

---

## Scaling

### Manual Scaling

```bash
kubectl scale deployment omniflow-frontend -n omniflow-dev --replicas=5
```

Note: If HPA is enabled, it will override manual scaling within 60 seconds. To manually control replicas, disable HPA first.

### Generate Load to Test HPA

```bash
kubectl run load-generator --image=busybox --restart=Never -n omniflow-dev -- \
  /bin/sh -c "while true; do wget -q -O- http://omniflow-frontend:80; done"
```

Watch in k9s: `:hpa` — you'll see replicas scale from 1 → 3.

What's happening:
1. Load generator sends continuous HTTP requests to the Service
2. Pod CPU usage rises above 70% (the HPA target)
3. HPA calculates new desired replicas: `ceil(current × current_util / target_util)`
4. Deployment creates additional pods
5. Service load-balances across all ready pods
6. CPU per pod drops below 70%
7. After 5 minutes of low utilization, HPA scales back down (10% at a time)

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

**Rollout sequence with `maxSurge=1, maxUnavailable=0`:**
1. New pod starts (total = N+1)
2. New pod passes readiness probe
3. Service adds new pod to endpoints, starts sending traffic
4. Old pod receives SIGTERM, gets 30s to drain
5. Old pod removed from Service endpoints
6. Old pod terminates
7. Repeat for each old pod

### Rollback

```bash
kubectl rollout history deployment/omniflow-frontend -n omniflow-dev
kubectl rollout undo deployment/omniflow-frontend -n omniflow-dev
```

**With Helm:**
```bash
helm history omniflow-frontend --namespace omniflow-dev
helm rollback omniflow-frontend <revision> --namespace omniflow-dev
```

**With Terraform:** Revert the code change and run `terraform apply`. Terraform calculates the diff and applies the reverse change.

---

## Troubleshooting

### Pod CrashLoopBackOff — Permission Denied on Port 80

**Symptom:** `bind() to 0.0.0.0:80 failed (13: Permission denied)`

**Cause:** Container runs as non-root (UID 1001). Linux prevents binding to ports < 1024.

**Fix:** nginx.conf uses `listen 8080`, Dockerfile has `EXPOSE 8080`, Service maps 80→8080.

**Why not just run as root?** Running as root in a container is still running as root on the host kernel. A container escape + root user = full host compromise. Non-root + read-only filesystem + dropped capabilities = defense in depth.

### Pod ImagePullBackOff

```bash
kind load docker-image ghcr.io/nkwatambe/omniflow-k8s-devops:local --name omniflow
kubectl patch deployment omniflow-frontend -n omniflow-dev \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "Never"}]'
```

**Why this happens:** By default, K8s tries to pull the image from the registry. In kind, the image is loaded locally, not in a registry. `imagePullPolicy: Never` tells K8s to use the local image.

### Ingress Not Working

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s
```

**Why this happens:** kind doesn't include an Ingress controller by default. The Ingress resource is just a rule — you need the controller (nginx) to actually route traffic.

### HPA Shows `<unknown>` Metrics

**Cause:** Metrics server not installed. HPA needs the metrics server to read CPU/memory usage.

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
```

The `--kubelet-insecure-tls` flag is needed in kind because the kubelet uses self-signed certificates.

### NetworkPolicy Blocks Legitimate Traffic

**Symptom:** Pod can't reach a backend API or external service that it needs.

**Cause:** The default egress only allows DNS. You must add rules for any outbound traffic the frontend needs.

**Fix:** Add egress rules in the Terraform module or Helm values:
```yaml
# Example: allow HTTPS to external APIs
egress:
  - to:
      - ipBlock:
          cidr: 0.0.0.0/0
          except: ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
    ports:
      - port: 443
        protocol: TCP
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

  Security:   non-root (UID 1001) + read-only FS + drop ALL caps + seccomp + NetworkPolicy
  Reliability: 3 health probes + rolling updates (maxSurge=1, maxUnavailable=0) + HPA
  Observability: Prometheus scrape annotations + /health endpoint + k9s visualization
```
