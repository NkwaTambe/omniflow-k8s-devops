# OmniFlow – Final Presentation Slide Deck
> Full slide-by-slide content with enriched context drawn directly from the codebase.
> Replace each `{{IMG:…}}` token with the corresponding screenshot or diagram.

---

## Slide 0 – Introduction

**OmniFlow – End-to-End Local Deployment Stack**

- A production-grade DevOps pipeline built entirely on open-source tooling — no cloud account required to run locally
- Full stack: Docker → kind → Kubernetes ↔ Terraform ↔ Helm → k9s
- Mirrors a real production environment (AWS EKS equivalent) on a developer laptop
- Core goals: rapid iteration, reproducible environments, and zero-downtime releases via rolling updates
- Frontend: React 19 + Vite 8, containerized and served by Nginx on Alpine Linux
- Image published to **GitHub Container Registry** (`ghcr.io/nkwatambe/omniflow-k8s-devops`)
- Prepared by **Ariel** — 2026-06-02

{{IMG:intro_logo}}

---

## Slide 1 – Tools Used

| Tool | Version | Role |
|------|---------|------|
| **Docker** | 20+ | Multi-stage builds — Node 20 Alpine builder → Nginx 1.28 Alpine production image |
| **kind** | 0.20+ | Spins up a real 2-node Kubernetes cluster (1 control-plane + 1 worker) inside Docker containers |
| **Kubernetes** | 1.29+ | Orchestration: RollingUpdate deployments, HPA (3–10 replicas), self-healing probes, NetworkPolicy |
| **Terraform** | ≥1.5 | Declarative IaC — provisions namespace, ConfigMap, ServiceAccount, Deployment, Service, HPA, NetworkPolicy, and Helm releases |
| **Helm** | 3.14+ | Chart `omniflow-frontend v1.0.0` — packages all K8s manifests into a versioned, reusable release |
| **k9s** | 0.32+ | Terminal UI for real-time pod inspection, log tailing, and resource monitoring |
| **Grafana + Prometheus** | kube-prometheus-stack 55.6.0 | Full observability stack — dashboards on NodePort 30030, metrics on 30031, alerts on 30032 |
| **Autocannon** | via npx | HTTP load testing — 100 concurrent virtual users over 30 seconds |
| **GitHub Actions** | — | Two pipelines: `ci.yml` (lint → test → build → deploy) and `security.yml` (audit → SBOM → CodeQL) |
| **Trivy** | — | Container image and filesystem vulnerability scanning, SARIF results posted to GitHub Security tab |

{{IMG:tool_logos}}

---

## Slide 2 – What We'll Cover

1. Project Overview — purpose & high-level flow
2. Team Organization & Communication
3. Architecture Diagram
4. GitHub Workflow (branching, CI/CD pipelines)
5. Build Process (Dockerfile, kind cluster)
6. Testing Strategy (unit, integration, load)
7. Release Management (Helm chart + Terraform state)
8. Docker & Deployment (kind load, Terraform vars)
9. Operations & Orchestration (K8s HPA, self-healing)
10. Monitoring & Grafana (Prometheus stack, custom alerts)
11. Load Testing (100 virtual users, 30 s)
12. Performance Results (Before vs After optimization)
13. Challenges Encountered
14. Lessons Learned
15. Future Improvements
16. Conclusion

{{IMG:agenda_diagram}}

---

## Slide 3 – Project Overview

**What is OmniFlow?**

OmniFlow is a complete, end-to-end DevOps pipeline for a React/Vite frontend application. Every layer — from source code to running pod — is automated and reproducible.

**The full flow in one line:**
```
git push → GitHub Actions → Docker build → ghcr.io → Helm → Kubernetes → Running pods
```

**Local equivalent (no cloud account needed):**
```
docker build → kind load → terraform apply → Helm chart → K8s pods → k9s
```

**Three deployment paths, all producing identical K8s resources:**
- **Path A – Terraform** (`terraform apply`): drift detection via `.tfstate`, idempotent, recommended for local dev
- **Path B – Helm** (`helm upgrade --install`): used by CI/CD for staged rollouts to staging → production
- **Path C – Kustomize** (`kubectl apply -k`): environment overlays (dev/staging/prod patches) for quick throwaway tests

**Key design principles:**
- Non-root containers (UID 1001) and read-only root filesystems
- Resource requests/limits on every pod (50m CPU / 64Mi RAM requests; 200m / 128Mi limits)
- Topology spread constraints prevent all replicas from landing on the same node
- NetworkPolicy restricts egress to DNS-only (port 53) — no unintended outbound traffic

{{IMG:project_overview}}

---

## Slide 4 – Team Organization and Communication

**Roles**

| Role | Responsibilities |
|------|----------------|
| DevOps Engineer (Ariel) | Pipeline design, Terraform modules, Helm chart, monitoring stack, load testing |
| Frontend Engineer | React/Vite application, component tests, Dockerfile |
| QA / Test Engineer | Integration tests, load test scenarios, coverage reporting |

**Communication**
- Slack channel: `#omniflow-dev` for async day-to-day discussion
- Weekly sync: review PR queue, deployment status, alert noise
- GitHub Issues: task tracking — every feature or bug has an issue; PRs reference the issue

**Branching Strategy — Trunk-Based Development**
- `main` — always deployable; protected branch, direct pushes blocked
- `feature/*` — short-lived (< 2 days); open PR → CI must pass → code review → merge
- `epic/*` — longer-lived branches for multi-sprint work, merged via sub-PRs

**PR Requirements (enforced by CI):**
- ESLint + TypeScript type-check must pass
- Vitest unit tests with coverage must pass
- Trivy security scan (CRITICAL/HIGH severity) must pass
- Container image must build successfully
- At least 1 reviewer approval required before merge

{{IMG:team_chart}}

---

## Slide 5 – Architecture Diagram

**Layer-by-layer breakdown:**

```
┌─────────────────────────────────────────────────────────────────┐
│                        OmniFlow DevOps System                    │
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────────────┐│
│  │   Terraform   │──▶│     Helm     │──▶│    Kubernetes (K8s)   ││
│  │  (Provision)  │   │  (Package)   │   │   (Orchestrate)      ││
│  └──────┬───────┘   └──────┬───────┘   └──────────┬───────────┘│
│         │   Provisions     │  Installs app          │  Runs pods │
│         ▼                  ▼                        ▼             │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    kind Cluster (2 nodes)                  │  │
│  │  Namespace ── ConfigMap ── Deployment ── Service ── HPA  │  │
│  │  NetworkPolicy ── Ingress ── ServiceAccount              │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

**Data flow (code to running UI):**
1. Developer pushes code → GitHub Actions triggers
2. Actions: lint → unit tests → `docker build` (multi-stage, Node 20 → Nginx Alpine)
3. Image tagged `sha-<commit>` and `latest`, pushed to `ghcr.io`
4. Terraform reads `image_tag` variable → calls Kubernetes + Helm providers
5. Helm renders chart templates → applies Deployment, Service, HPA, Ingress, NetworkPolicy
6. K8s schedules pods across control-plane + worker nodes (topology spread)
7. Nginx serves the static React build on port 8080; liveness + readiness probes on `/health`
8. HPA watches CPU (target 70%) and memory (target 80%) → scales 3–10 replicas
9. Prometheus scrapes `/health` metrics → Grafana dashboards visualize; Alertmanager fires on thresholds

**Security layers baked in:**
- `seccompProfile: RuntimeDefault` on every pod
- `readOnlyRootFilesystem: true` — writable mounts only for `/tmp`, `/var/cache/nginx`, `/var/run`
- `capabilities.drop: [ALL]` — no Linux capabilities granted
- `automountServiceAccountToken: false` — nginx has no reason to call the K8s API

{{IMG:arch_diagram}}

---

## Slide 6 – GitHub Workflow

**Repository structure:**
```
omniflow-k8s-devops/
├── .github/workflows/   # ci.yml + security.yml
├── src/                 # React/Vite app + Dockerfile
├── helm/                # omniflow-frontend Helm chart v1.0.0
├── k8s/                 # base manifests + dev/staging/prod overlays (Kustomize)
├── terraform/           # modules: frontend, ingress, monitoring, namespace
├── monitoring/          # kube-prometheus-stack wrapper chart + custom alerts
└── docs/                # local-deployment, monitoring, load-testing, workflow guides
```

**CI Pipeline (`ci.yml`) — triggers: PR to main, push to main**

| Job | Runs on | What it does |
|-----|---------|-------------|
| `lint` | Every PR + push | ESLint + `tsc --noEmit` type check |
| `test` | Every PR + push | Vitest with coverage; artifact uploaded for 7 days |
| `security-scan` | Every PR + push | Trivy FS scan + config scan (Docker/K8s/Terraform misconfigs) |
| `build` | After lint + test pass | `docker buildx build`; push to ghcr.io only on merge to `main`; Trivy image scan |
| `deploy-staging` | After build + security pass, on `main` only | `helm upgrade --install` with `values-staging.yaml` + SHA tag |
| `deploy-production` | After staging deploy, on `main` only | `helm upgrade --install` with `values-prod.yaml`; smoke test via `wget /health` |

**Security Pipeline (`security.yml`) — also runs weekly (Sunday midnight):**
- `npm audit --audit-level=high` — catches new CVEs in dependencies
- `trivy fs` in SPDX-JSON format → SBOM artifact (retained 30 days)
- CodeQL analysis for JavaScript — detects XSS, path traversal, injection patterns

**Key decision — push to ghcr.io only on merge to main:**
No half-finished PR images in the registry. The `:latest` tag always points to production-ready code.

{{IMG:github_workflow}}

---

## Slide 7 – Build Process

**Multi-stage Dockerfile (`src/Dockerfile`)**

```
Stage 1 — builder (node:20-alpine3.20)
  ├── COPY package*.json → npm ci (clean install, respects lockfile)
  ├── COPY . .
  └── RUN npm run build  → produces /app/dist (static HTML/JS/CSS)

Stage 2 — production (nginx:1.28.0-alpine3.21)
  ├── apk update && apk upgrade  (patch Alpine CVEs at build time)
  ├── addgroup/adduser → UID/GID 1001 (non-root)
  ├── COPY nginx.conf → custom server block
  ├── COPY --from=builder /app/dist → /usr/share/nginx/html  (only the built assets)
  ├── USER appuser
  ├── HEALTHCHECK wget http://localhost:8080/health
  └── EXPOSE 8080
```

**Why multi-stage?**
- Final image contains zero Node.js, npm, or build tools — only Nginx + static files
- Eliminates the largest attack surface (node_modules in production)
- Image is dramatically smaller: ~25 MB vs ~350 MB with a single-stage Node image

**Local build and load into kind:**
```bash
# Build with the same name as the CI/CD registry path (consistency)
docker build -t ghcr.io/nkwatambe/omniflow-k8s-devops:local ./src

# Load directly into kind cluster nodes (no registry needed locally)
kind load docker-image ghcr.io/nkwatambe/omniflow-k8s-devops:local --name omniflow
```

**The `kind load` step is critical** — kind nodes are Docker containers without direct access to your local Docker daemon. Without `kind load`, K8s would try to pull from ghcr.io and fail with `ImagePullBackOff`.

**Image tag strategy:**

| Context | Tag | Set by |
|---------|-----|--------|
| Local dev | `:local` | Developer |
| Pull Request build | `:sha-<commit>` | GitHub Actions `docker/metadata-action` |
| Merge to main | `:sha-<commit>` + `:latest` | GitHub Actions |
| Dev environment (Helm) | `:dev` | `values-dev.yaml` |
| Production | `:latest` | `values-prod.yaml` |

{{IMG:dockerfile_frontend}}

---

## Slide 8 – Testing Strategy

**Unit Tests — Vitest + React Testing Library**
- Framework: Vitest 4.x (Vite-native, no Jest config overhead)
- Environment: `happy-dom` (fast, no real browser needed)
- Location: `src/src/App.test.tsx`, `src/tests/unit/App.test.tsx`
- Example tests:
  - Renders the `Vite + React` heading
  - Renders the counter button with correct label
- Coverage: text + JSON + HTML reporters; excludes `node_modules/` and test setup files
- Run: `npm run test:coverage` → uploads coverage artifact to GitHub Actions (7-day retention)

**Integration Tests — `src/tests/integration.test.ts`**
- Tests full component rendering and DOM presence
- Verifies the main heading renders correctly end-to-end
- Same Vitest runner — no separate tooling needed

**Load Testing — Autocannon via `docs/scripts/run-load-test.sh`**
```bash
# The script does all three steps automatically:
# 1. Kills any existing process on port 8080
# 2. kubectl port-forward svc/omniflow-frontend 8080:80 (background)
# 3. npx autocannon -c 100 -d 30 --latency --renderStatusCodes http://localhost:8080/
```
- 100 concurrent connections, 30-second duration
- Reports: avg latency, 97.5th/99th percentile, max latency, req/sec, data throughput, status codes

**CI runs all suites on every PR:**
- `lint` → `test` → `security-scan` → `build` jobs must all pass before merge is allowed
- Trivy config-mode scan checks Dockerfile, K8s manifests, and Terraform for misconfigurations
- CodeQL weekly scan catches security issues that static linting misses

{{IMG:test_report}}

---

## Slide 9 – Release Management

**Helm Chart — `helm/omniflow-frontend` v1.0.0**

`Chart.yaml` defines:
- `version: 1.0.0` — chart version (bump when chart structure changes)
- `appVersion: "1.0.0"` — tracks the application version
- Maintainer: `NkwaTambe`; keywords: `omniflow, frontend, react, vite, kubernetes`

**Per-environment values files:**

| File | Replicas | CPU Limit | Memory Limit | HPA max | Host |
|------|----------|-----------|-------------|---------|------|
| `values-dev.yaml` | 1 | 100m | 64Mi | 3 | omniflow.dev.local |
| `values-staging.yaml` | 2 | 200m | 128Mi | 6 | omniflow.staging.local |
| `values-prod.yaml` | 3 | 500m | 256Mi | 10 | omniflow.example.com |

**Deploy flow (CI/CD):**
1. Code merged to `main` → Actions `build` job pushes image tagged `sha-<commit>` to ghcr.io
2. `deploy-staging` job runs:
   ```bash
   helm upgrade --install omniflow-frontend ./helm/omniflow-frontend \
     --namespace omniflow-staging --create-namespace \
     -f values-staging.yaml --set image.tag=sha-<commit> --wait --timeout 300s
   ```
3. `kubectl rollout status` verifies all pods are ready
4. `deploy-production` follows only after staging succeeds

**Rollback:** `helm rollback omniflow-frontend <revision>` — Helm keeps full release history in the cluster as Kubernetes Secrets

**Terraform tracks state:** `terraform.tfstate` records the exact `image_tag` deployed. Running `terraform plan` after a manual `kubectl edit` will show the drift and offer to revert it.

{{IMG:helm_release}}

---

## Slide 10 – Docker and Deployment

**Step-by-step local deployment:**

```bash
# 1. Create the 2-node kind cluster (control-plane + worker)
kind create cluster --name omniflow --config kind-config.yaml --wait 120s

# 2. Verify nodes are Ready
kubectl get nodes

# 3. Build the multi-stage image
docker build -t ghcr.io/nkwatambe/omniflow-k8s-devops:local ./src

# 4. Load image into kind (bypasses registry requirement)
kind load docker-image ghcr.io/nkwatambe/omniflow-k8s-devops:local --name omniflow

# 5. Terraform: provision all K8s resources + Helm release
cd terraform/environments/dev
terraform init
terraform plan -var="image_tag=local"
terraform apply -var="image_tag=local"

# 6. Verify pods are running
kubectl get pods -n omniflow-dev
```

**`kind-config.yaml` — why 2 nodes matter:**
```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
```
- Single-node kind = topology spread constraints fail → pods stuck `Pending`
- 2-node setup mirrors production (separate control plane + worker nodes)
- Pods run on the worker node; control-plane handles API/etcd/scheduler

**Terraform module responsibilities (`terraform/modules/frontend/main.tf`):**
- `kubernetes_config_map` — injects `NODE_ENV=production`, `VITE_APP_TITLE=OmniFlow`, nginx worker settings
- `kubernetes_service_account` — dedicated identity, `automountServiceAccountToken = false`
- `kubernetes_deployment` — rolling update strategy (`maxSurge=1`, `maxUnavailable=0`), topology spread, all 3 probes
- `kubernetes_service` — ClusterIP type, port 80 → pod port 8080
- `kubernetes_horizontal_pod_autoscaler_v2` — CPU 70% / memory 80% targets, scale up 100% per 60s, scale down 10% per 60s (5-min cooldown)
- `kubernetes_network_policy` — ingress from nginx-ingress only; egress to kube-system DNS (port 53) only

**k9s** — after `terraform apply`, run `k9s` to see all pods, logs, events, and resource usage in a live terminal dashboard.

{{IMG:kind_config}}

---

## Slide 11 – Operations and Orchestration

**Kubernetes deployment configuration (from `k8s/base/deployment.yaml`):**

- `strategy: RollingUpdate` with `maxSurge: 1, maxUnavailable: 0` — always at least 3 pods serving traffic during an update; new pod comes up before any old pod goes down
- **3 health probes on every pod:**
  - `startupProbe`: checks `/health` every 5s, up to 12 failures (60s grace) — prevents premature liveness kills during cold start
  - `livenessProbe`: checks `/health` every 30s — restarts the pod if Nginx becomes unresponsive
  - `readinessProbe`: checks `/health` every 10s — removes pod from Service endpoints if it's not ready to handle traffic
- `topologySpreadConstraints`: `maxSkew: 1` across `kubernetes.io/hostname` — replicas are spread evenly; a node failure takes out at most ⌊n/2⌋ pods

**HPA configuration (from `k8s/base/hpa.yaml`):**

| Parameter | Value |
|-----------|-------|
| Min replicas | 3 |
| Max replicas | 10 |
| CPU scale-up trigger | >70% average utilization |
| Memory scale-up trigger | >80% average utilization |
| Scale-up window | 60s (doubles replica count per minute maximum) |
| Scale-down window | 300s (5-min cooldown, reduces by 10% per minute) |

The asymmetric scale policy (fast up, slow down) prevents thrashing — traffic spikes get capacity immediately; the system doesn't shed replicas the moment traffic dips.

**NetworkPolicy (`k8s/base/networkpolicy.yaml`):**
- Ingress allowed only from: `ingress-nginx` pods OR pods in the `omniflow-platform` namespace
- Egress allowed only to: `kube-system` namespace on port 53 (DNS resolution)
- Everything else is implicitly denied — no accidental data exfiltration, no lateral movement

**Namespace isolation:** `omniflow-dev`, `omniflow-staging`, `omniflow-prod` are fully separate K8s namespaces. A misconfigured pod in dev cannot reach services in prod.

{{IMG:k8s_arch}}

---

## Slide 12 – Monitoring and Grafana

**Stack:** `kube-prometheus-stack v55.6.0` wrapped in `monitoring/` Helm chart

**Three endpoints (NodePort on kind):**

| Service | URL | Credentials |
|---------|-----|------------|
| Grafana | http://localhost:30030 | admin / prom-operator |
| Prometheus | http://localhost:30031 | no auth |
| Alertmanager | http://localhost:30032 | no auth |

**What Prometheus scrapes automatically:**
- Node Exporter → host CPU, RAM, disk I/O, network
- kube-state-metrics → pod status, deployment replica counts, restart counts
- kubelet/cAdvisor → per-container CPU and memory usage
- API Server, CoreDNS → request rates, DNS failures
- OmniFlow pods → annotated with `prometheus.io/scrape: "true"` on `/health:80`

**Custom alert rules (`monitoring/templates/omniflow-alerts.yaml`) — 7 rules in 3 groups:**

| Group | Alert | Threshold | Severity |
|-------|-------|-----------|----------|
| Pod Health | `OmniFlowPodDown` | 0 available replicas for 1 min | Critical |
| Pod Health | `OmniFlowPodCrashLooping` | restart rate > 0 over 5 min | Warning |
| Resources | `OmniFlowHighCPU` | >80% of CPU limit for 5 min | Warning |
| Resources | `OmniFlowHighMemory` | >85% of memory limit for 5 min | Warning |
| Cluster | `HighNodeCPU` | >90% node CPU for 10 min | Critical |
| Cluster | `HighNodeMemory` | >90% node memory for 10 min | Critical |
| Cluster | `HighDiskUsage` | >85% filesystem for 10 min | Warning |

**Pre-built Grafana dashboards used in this project:**
- `Kubernetes / Compute Resources / Namespace (Workloads)` — used during load testing to watch live CPU/memory
- `Node Exporter / Nodes` — host-level metrics during stress tests
- `Kubernetes / Compute Resources / Cluster` — overall cluster health view

**Alert flow:** PrometheusRule → Prometheus evaluates every 30s → condition met for `for:` duration → Alertmanager receives → routes to configured receiver (Slack/email/webhook)

{{IMG:grafana_dashboard}}

---

## Slide 13 – Load Testing (100 Users)

**Tool:** Autocannon (Node.js HTTP/1.1 benchmarking tool, zero install via `npx`)

**Test configuration:**
```bash
npx autocannon -c 100 -d 30 --latency --renderStatusCodes http://localhost:8080/
# -c 100  → 100 concurrent connections (virtual users)
# -d 30   → 30-second duration
# --latency → prints full latency histogram (avg, p50, p97.5, p99, max)
# --renderStatusCodes → shows breakdown of HTTP response codes
```

**What the load test script does (`docs/scripts/run-load-test.sh`):**
1. Checks if port 8080 is already in use — kills the old process if so
2. Starts `kubectl port-forward svc/omniflow-frontend 8080:80` in the background
3. Waits 3 seconds for the tunnel to stabilize
4. Health-checks `http://localhost:8080/health` before starting — exits if app is down
5. Runs Autocannon and prints the results table
6. Cleans up the background port-forward on exit (trap on EXIT signal)

**What to observe in Grafana during the test:**
1. Open http://localhost:30030 → `Kubernetes / Compute Resources / Namespace (Workloads)`, filter: `omniflow-dev`
2. Watch CPU usage hit the ceiling on single-pod (before optimization) vs distribute across 3 pods (after)
3. Watch HPA replica count metric climb from 3 → 6 as CPU crosses 70%
4. Watch request rate and network throughput charts spike

**After optimization results:**
- Total requests in 30s: **83,000** (vs 15,000 before — 5.5x more served)
- Requests per second: **2,766** (vs 491 before)
- Average latency: **35.88 ms** (vs 202.94 ms before — 82% faster)
- Zero HTTP errors or connection drops

{{IMG:load_test_results}}

---

## Slide 14 – Performance Results (Before vs After)

**Environment parameters changed:**

| Parameter | Before (under-provisioned) | After (optimized) |
|-----------|---------------------------|-------------------|
| Replicas | 1 | 3 |
| CPU Request | 25m | 100m |
| CPU Limit | 100m | 500m |
| Memory Request | 32Mi | 64Mi |
| Memory Limit | 64Mi | 256Mi |
| HPA min / max | 1 / 3 | 3 / 6 |

**Load test results (100 concurrent users, 30s):**

| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Total requests | 15,000 | 83,000 | **+453%** |
| Successful (200 OK) | 14,718 | 82,970 | **+463%** |
| Avg latency | 202.94 ms | 35.88 ms | **−82.3%** |
| 97.5th percentile | 599 ms | 85 ms | **−85.8%** |
| 99th percentile | 697 ms | 91 ms | **−86.9%** |
| Max latency | 1047 ms | 1033 ms | −1.3% |
| Throughput (req/s) | 490.60 | 2,766.20 | **+464%** |
| Data throughput | 342 kB/s | 1.93 MB/s | **+464%** |
| Error rate | ~2% | 0% | Eliminated |

**Root cause of "Before" degradation:**
- Single pod CPU limit of `100m` = 10% of one CPU core
- Nginx event loop saturated immediately at 100 concurrent connections
- Requests queued behind each other → avg latency ballooned to 202 ms, tail to 697 ms
- Single replica = single point of failure; one pod restart = full service outage

**Why "After" is faster:**
- 3 replicas distribute the 100 concurrent connections (~33 each)
- CPU limit of `500m` per pod gives Nginx's workers room to process requests without throttling
- HPA can scale to 6 replicas if CPU stays above 70% → system self-tunes under sustained load
- 5-minute scale-down cooldown prevents flapping between traffic bursts

{{IMG:perf_comparison}}

---

## Slide 15 – Challenges Encountered

**1. Aligning Terraform `image_tag` variable with Helm values**
- Problem: Terraform's `kubernetes_deployment` resource and the Helm `helm_release` resource both manage the image tag, but via different mechanisms (HCL variable vs Helm `--set`)
- Fix: Standardized on a single `image_tag` Terraform variable that flows through to both providers; added `checksum/config` annotation on the pod template so any config change triggers a rolling restart

**2. `imagePullPolicy` mismatch in kind**
- Problem: Helm and Terraform default to `imagePullPolicy: Always`. Kind nodes have no access to ghcr.io unless credentials are configured. This caused `ImagePullBackOff` on local deployments.
- Fix: Kustomize patch in `k8s/overlays/dev/kustomization.yaml` overrides the policy to `Never` for dev; image must be pre-loaded with `kind load docker-image`

**3. k9s view latency with many CRDs**
- Problem: The `kube-prometheus-stack` deploys dozens of CRDs (PrometheusRule, ServiceMonitor, Alertmanager, etc.) which slowed k9s list views
- Fix: Use k9s namespace filter (`:omniflow-dev`) to scope the view; bookmark the relevant resource kinds

**4. Topology spread constraints blocking pod scheduling on single-node kind**
- Problem: `topologySpreadConstraints` with `whenUnsatisfiable: DoNotSchedule` requires at least as many nodes as the `maxSkew` spread demands. Single-node kind → pods stuck `Pending`
- Fix: `kind-config.yaml` with explicit `control-plane + worker` node roles

**5. Trivy CI scan false positives blocking PRs**
- Problem: Some Alpine package CVEs were unfixable (upstream not patched) but Trivy was blocking the build pipeline
- Fix: Added `.trivyignore` file to suppress known, accepted CVEs; used `--ignore-unfixed: true` flag in the image scan step

**6. Reproducible builds across operating systems**
- Problem: `npm ci` on macOS vs Linux produced subtly different `package-lock.json` entries, causing CI failures
- Fix: Locked Node.js to version 20 in both the Dockerfile (`FROM node:20-alpine3.20`) and GitHub Actions (`node-version: '20'`)

{{IMG:challenge_screenshot}}

---

## Slide 16 – Lessons Learned

**1. Terraform as the single source of truth eliminates configuration drift**
The three-way comparison (declared code ↔ `.tfstate` ↔ live K8s API) catches manual changes that bypass the pipeline. Running `terraform plan` after any manual `kubectl edit` immediately reveals the drift and shows exactly what will be reverted.

**2. Multi-stage Docker builds are non-negotiable for production**
The builder stage (Node 20 + 300 MB of node_modules) never makes it into the final image. The production image is Nginx Alpine + static files only — ~25 MB, minimal attack surface, and drastically faster pull times in CI/CD.

**3. Resource requests and limits are prerequisites for HPA, not optional**
HPA requires `resources.requests.cpu` to calculate utilization percentages. Pods without resource requests are invisible to the autoscaler. Setting proper limits also prevents one noisy pod from starving its neighbors on the same node.

**4. Monitoring dashboards caught issues the tests didn't**
During load testing, Grafana's `container_cpu_throttled_seconds_total` metric revealed that the pod was hitting its CPU ceiling seconds before latency metrics degraded visibly. Alerts on resource thresholds caught this before users would have noticed.

**5. Topology spread constraints are essential for zero-downtime rolling updates**
Without spreading replicas across nodes, K8s could schedule all 3 replicas on the same worker. A node failure would then take down the entire service. `maxSkew: 1` ensures at most 1 more replica lands on any one node.

**6. The `--wait` flag in `helm upgrade` is critical for CI/CD reliability**
Without `--wait`, the Helm step succeeds as soon as the chart is applied, even if pods are still `Pending` or `CrashLooping`. `--wait --timeout 300s` blocks the pipeline until the deployment is truly healthy.

{{IMG:lessons_diagram}}

---

## Slide 17 – Future Improvements

**1. Push Docker images to a remote registry in CI (GitHub Packages)**
Already partially implemented — `ci.yml` pushes to `ghcr.io` on merge to `main`. Next step: configure staging/prod Kubernetes clusters with the GHCR pull secret so Helm deployments pull from the registry automatically without `kind load`.

**2. Migrate kind → managed EKS/GKE for staging**
The Terraform modules are already written with the Kubernetes and Helm providers — switching from kind to a cloud cluster requires only changing the provider `host` and authentication credentials in `terraform/environments/staging/`. No module changes needed.

**3. Canary deployments with Argo Rollouts**
Replace the `Deployment` resource with an Argo `Rollout` configured for canary strategy: 10% → 30% → 100% traffic shift with Prometheus success-rate metrics as the promotion gate. Failed canaries auto-rollback without human intervention.

**4. Chaos engineering with Litmus**
Expand the test suite beyond load testing to failure scenarios: random pod kills, node network partitions, CPU stress injection. Validate that the HPA and self-healing probes behave correctly under real failure conditions, not just under load.

**5. Secret management with HashiCorp Vault or External Secrets Operator**
Currently, sensitive values (TLS certs, future API keys) are stored in Kubernetes Secrets (base64, not encrypted at rest). Integrate Vault or External Secrets Operator to pull secrets from a secure backend and rotate them without redeploying.

**6. Expand Grafana dashboards with SLO tracking**
Define explicit SLOs (e.g., 99.9% of requests < 100 ms, 0 pod restarts per day) and add Grafana panels that track error budget burn rate. Alert when the error budget drops below a threshold, not just when individual metrics spike.

{{IMG:future_roadmap}}

---

## Slide 18 – Conclusion

**OmniFlow demonstrates a complete, production-grade DevOps workflow from a single `git push` to a running, monitored, auto-scaling UI — entirely on a developer laptop.**

**What was built:**
- A React 19 / Vite 8 frontend packaged in a hardened, non-root Nginx Alpine container (~25 MB)
- A kind-based local Kubernetes cluster that faithfully mirrors an AWS EKS production environment
- Terraform modules that provision every K8s resource declaratively, detect drift, and guarantee idempotency
- A Helm chart with per-environment values (dev / staging / prod) and full rollback capability
- A two-pipeline GitHub Actions CI/CD system with lint, test, security scanning (Trivy + CodeQL), build, and staged deployment
- A full observability stack (Prometheus + Grafana + Alertmanager) with 7 custom alert rules
- Validated performance: 5.5x more requests served, 82% lower average latency, 0% error rate after optimization

**The result:** A local stack that mirrors production — hand-off to a cloud environment requires changing a Terraform provider config, nothing else. Robust monitoring, HPA-driven scaling, and Helm-managed rollbacks guarantee reliability from day one.

**Ready for next-generation features:** canary releases, EKS migration, chaos testing, and SLO-driven alerting are all within reach with the foundation built here.

{{IMG:final_slide}}

---
*End of Deck — Replace each `{{IMG:…}}` placeholder with the corresponding screenshot: Dockerfile in editor, k9s terminal view, Grafana dashboard, load test output table, kind node listing, GitHub Actions run summary, etc.*
