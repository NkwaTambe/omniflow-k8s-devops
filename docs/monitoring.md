# Monitoring Stack – Prometheus, Grafana & Alertmanager

> **Project**: OmniFlow K8s DevOps  
> **Namespace**: `monitoring`  
> **Helm Chart**: `monitoring` (wraps `kube-prometheus-stack v55.6.0`)

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Components](#components)
4. [Directory Structure](#directory-structure)
5. [Helm Chart Configuration](#helm-chart-configuration)
6. [Custom Alerting Rules](#custom-alerting-rules)
7. [Accessing the Dashboards](#accessing-the-dashboards)
8. [Pre-built Grafana Dashboards](#pre-built-grafana-dashboards)
9. [Deployment & Upgrade](#deployment--upgrade)
10. [Verification Checklist](#verification-checklist)

---

## Overview

The OmniFlow monitoring stack provides **full observability** into the Kubernetes cluster and the OmniFlow Frontend application. It is deployed as a Helm chart that wraps the community-maintained [`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) chart.

The stack delivers three core capabilities:

| Capability | Tool | Purpose |
|-----------|------|---------|
| **Metrics collection** | Prometheus | Scrapes and stores time-series metrics from all cluster components |
| **Visualization** | Grafana | Provides dashboards for real-time and historical metric exploration |
| **Alerting** | Alertmanager | Evaluates alert rules and routes notifications when thresholds are breached |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                      Kubernetes Cluster                          │
│                                                                  │
│  ┌─────────────┐    scrapes     ┌──────────────────────────┐     │
│  │ Node        │ ◄──────────── │                          │     │
│  │ Exporter    │               │       Prometheus         │     │
│  └─────────────┘               │   (metrics database)     │     │
│                                │                          │     │
│  ┌─────────────┐    scrapes    │  ┌──────────────────┐    │     │
│  │ kube-state  │ ◄──────────── │  │ PrometheusRule   │    │     │
│  │ -metrics    │               │  │ (omniflow-alerts)│    │     │
│  └─────────────┘               │  └──────────────────┘    │     │
│                                │           │              │     │
│  ┌─────────────┐    scrapes    └───────────┼──────────────┘     │
│  │ kubelet /   │ ◄────────────             │                    │
│  │ cAdvisor    │              evaluates rules                   │
│  └─────────────┘                           │                    │
│                                            ▼                    │
│  ┌─────────────┐               ┌──────────────────┐            │
│  │ OmniFlow    │               │  Alertmanager     │            │
│  │ Frontend    │               │  (notifications)  │            │
│  │ Pods        │               └──────────────────┘            │
│  └─────────────┘                                                │
│                                ┌──────────────────┐            │
│                                │    Grafana        │            │
│                                │  (dashboards)     │            │
│                                └──────────────────┘            │
└──────────────────────────────────────────────────────────────────┘
```

**Data flow:**
1. **Prometheus** periodically scrapes metrics from Node Exporter, kube-state-metrics, kubelet/cAdvisor, and any configured ServiceMonitors.
2. **PrometheusRules** define alerting thresholds. When a condition is met for the specified duration, Prometheus fires an alert to **Alertmanager**.
3. **Alertmanager** deduplicates, groups, and routes alerts (e.g., to Slack, email, or PagerDuty).
4. **Grafana** queries Prometheus as a data source and renders dashboards.

---

## Components

### Prometheus

| Property | Value |
|----------|-------|
| **What it does** | Scrapes and stores time-series metrics from the cluster |
| **Service** | `monitoring-kube-prometheus-prometheus` |
| **Port** | `9090` |
| **NodePort** | `30031` |
| **Default metrics sources** | Node Exporter, kube-state-metrics, kubelet, cAdvisor, API server, CoreDNS |

**What Prometheus monitors out of the box:**

| Source | Metrics Collected |
|--------|-------------------|
| **Node Exporter** | Host CPU, RAM, disk I/O, network traffic, filesystem usage |
| **kube-state-metrics** | Pod status, deployment replica counts, restart counts, job status |
| **kubelet / cAdvisor** | Per-container CPU & memory usage, network per pod |
| **API Server** | Request latency, error rates, request counts |
| **CoreDNS** | DNS query rates, resolution failures |

### Grafana

| Property | Value |
|----------|-------|
| **What it does** | Visualizes metrics via dashboards |
| **Service** | `monitoring-grafana` |
| **Port** | `80` (forwards to `3000` internally) |
| **NodePort** | `30030` |
| **Default credentials** | Username: `admin`, Password: `prom-operator` |
| **Data source** | Prometheus (auto-configured) |

### Alertmanager

| Property | Value |
|----------|-------|
| **What it does** | Receives fired alerts from Prometheus, deduplicates, groups, and routes them |
| **Service** | `monitoring-kube-prometheus-alertmanager` |
| **Port** | `9093` |
| **NodePort** | `30032` |

---

## Directory Structure

```
monitoring/
├── Chart.yaml                          # Helm chart metadata + kube-prometheus-stack dependency
├── Chart.lock                          # Locked dependency versions
├── values.yaml                         # Custom configuration (ports, credentials, toggles)
├── charts/                             # Downloaded dependency charts (auto-managed)
│   └── kube-prometheus-stack-55.6.0.tgz
└── templates/
    └── omniflow-alerts.yaml            # Custom PrometheusRule for OmniFlow-specific alerts
```

---

## Helm Chart Configuration

### `Chart.yaml`

```yaml
apiVersion: v2
name: monitoring
description: Prometheus + Grafana stack for OmniFlow
type: application
version: 0.1.0
appVersion: "1.0.0"
dependencies:
  - name: kube-prometheus-stack
    version: "55.6.0"
    repository: "https://prometheus-community.github.io/helm-charts"
```

The chart has a single dependency: `kube-prometheus-stack`, which bundles Prometheus, Grafana, Alertmanager, Node Exporter, and kube-state-metrics.

### `values.yaml`

```yaml
# Grafana configuration
grafana:
  enabled: true
  adminUser: admin
  adminPassword: "admin"
  service:
    type: NodePort
    nodePort: 30030        # Access Grafana at http://localhost:30030
    port: 80
    targetPort: 3000

# Prometheus configuration
prometheus:
  enabled: true
  service:
    type: NodePort
    nodePort: 30031        # Access Prometheus at http://localhost:30031
    port: 9090
    targetPort: 9090

# Alertmanager configuration
alertmanager:
  enabled: true
  service:
    type: NodePort
    nodePort: 30032        # Access Alertmanager at http://localhost:30032
    port: 9093
    targetPort: 9093
```

**Key decisions:**
- All services use `NodePort` type for easy local access on a kind cluster.
- Grafana admin password is set to `admin` (in production, use a Kubernetes Secret).
- Alertmanager is enabled for alert routing capabilities.

---

## Custom Alerting Rules

Custom alerting thresholds are defined in `monitoring/templates/omniflow-alerts.yaml` as a `PrometheusRule` custom resource. These rules are automatically picked up by Prometheus.

### Group 1: Pod Health (`omniflow.pod.health`)

| Alert | Condition | Duration | Severity | Description |
|-------|-----------|----------|----------|-------------|
| **OmniFlowPodDown** | Available replicas of `omniflow-frontend` deployment = 0 | 1 min | 🔴 Critical | The frontend application has no running pods |
| **OmniFlowPodCrashLooping** | Container restart rate > 0 over 5 min window | 5 min | 🟡 Warning | The frontend container is repeatedly crashing and restarting |

### Group 2: Resource Usage (`omniflow.resources`)

| Alert | Condition | Duration | Severity | Description |
|-------|-----------|----------|----------|-------------|
| **OmniFlowHighCPU** | CPU usage > 80% of resource limit | 5 min | 🟡 Warning | The frontend is consuming most of its allocated CPU |
| **OmniFlowHighMemory** | Memory usage > 85% of resource limit | 5 min | 🟡 Warning | The frontend is consuming most of its allocated memory |

### Group 3: Cluster Health (`omniflow.cluster`)

| Alert | Condition | Duration | Severity | Description |
|-------|-----------|----------|----------|-------------|
| **HighNodeCPU** | Average node CPU utilization > 90% | 10 min | 🔴 Critical | The cluster nodes are under heavy CPU pressure |
| **HighNodeMemory** | Node memory utilization > 90% | 10 min | 🔴 Critical | The cluster nodes are running low on memory |
| **HighDiskUsage** | Node filesystem usage > 85% | 10 min | 🟡 Warning | A node disk is filling up |

### How alerts flow

```
PrometheusRule (omniflow-alerts.yaml)
    │
    ▼
Prometheus evaluates rules every 30s
    │
    ▼
Condition met for "for" duration?
    │
    ├── NO  → Alert stays INACTIVE
    │
    └── YES → Alert transitions to PENDING → then FIRING
                    │
                    ▼
              Alertmanager receives alert
                    │
                    ▼
              Routes to configured receivers
              (Slack, email, webhook, etc.)
```

### Modifying thresholds

To change a threshold, edit `monitoring/templates/omniflow-alerts.yaml`:

```yaml
# Example: lower the CPU threshold from 80% to 70%
- alert: OmniFlowHighCPU
  expr: |
    (...) * 100 > 70    # Changed from 80 to 70
  for: 5m
```

Then re-deploy:

```bash
helm upgrade monitoring ./monitoring -n monitoring -f ./monitoring/values.yaml
```

---

## Accessing the Dashboards

### Option A: NodePort (if configured)

| Dashboard | URL | Credentials |
|-----------|-----|-------------|
| **Grafana** | http://localhost:30030 | `admin` / `prom-operator` |
| **Prometheus** | http://localhost:30031 | No auth |
| **Alertmanager** | http://localhost:30032 | No auth |

### Option B: Port-Forward (if services are ClusterIP)

```bash
# Grafana
kubectl port-forward svc/monitoring-grafana -n monitoring 30030:80

# Prometheus
kubectl port-forward svc/monitoring-kube-prometheus-prometheus -n monitoring 30031:9090

# Alertmanager
kubectl port-forward svc/monitoring-kube-prometheus-alertmanager -n monitoring 30032:9093
```

Then open the same URLs as above in your browser.

---

## Pre-built Grafana Dashboards

The kube-prometheus-stack ships with **20+ pre-built dashboards**. Key dashboards to explore:

| Dashboard Name | What It Shows |
|----------------|---------------|
| **Kubernetes / Compute Resources / Cluster** | Cluster-wide CPU, memory, and network usage |
| **Kubernetes / Compute Resources / Namespace (Pods)** | Per-pod resource consumption within a namespace |
| **Kubernetes / Networking / Cluster** | Network traffic across the cluster |
| **Node Exporter / Nodes** | Detailed host-level metrics (CPU cores, RAM, disk, network interfaces) |
| **CoreDNS** | DNS resolution rates, cache hit ratios, failures |

### Importing additional dashboards

1. Navigate to **Grafana → ☰ → Dashboards → New → Import**
2. Enter a dashboard ID from [grafana.com/dashboards](https://grafana.com/grafana/dashboards/)
3. Select **Prometheus** as the data source
4. Click **Import**

Recommended community dashboards:

| Dashboard | ID | Description |
|-----------|----|-------------|
| Node Exporter Full | `1860` | Comprehensive node-level metrics |
| K8s Cluster Summary | `8685` | High-level cluster overview |
| Kubernetes Pods | `15760` | Per-pod resource usage breakdown |

---

## Deployment & Upgrade

### Initial deployment

```bash
# 1. Add the Prometheus community Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 2. Build chart dependencies
cd monitoring/
helm dependency build
cd ..

# 3. Deploy the monitoring stack
helm install monitoring ./monitoring \
  --namespace monitoring \
  --create-namespace \
  -f ./monitoring/values.yaml
```

### Upgrading (after changing values.yaml or alert rules)

```bash
helm upgrade monitoring ./monitoring \
  --namespace monitoring \
  -f ./monitoring/values.yaml
```

### Uninstalling

```bash
helm uninstall monitoring -n monitoring
kubectl delete namespace monitoring
```

---

## Verification Checklist

After deployment, verify the stack is healthy:

```bash
# 1. All pods running
kubectl get pods -n monitoring
# Expected: All pods show STATUS=Running, READY columns fully populated

# 2. Services exposed
kubectl get svc -n monitoring
# Expected: Grafana, Prometheus, Alertmanager services listed

# 3. Custom alert rules loaded
kubectl get prometheusrule -n monitoring
# Expected: "omniflow-alerts" appears in the list

# 4. Prometheus targets healthy
# Open http://localhost:30031 → Status → Targets
# Expected: All targets show State=UP

# 5. Grafana login works
# Open http://localhost:30030 → Login with admin / prom-operator
# Expected: Dashboards are visible and populated with data
```

### Expected pod output

```
NAME                                                     READY   STATUS    RESTARTS   AGE
alertmanager-monitoring-kube-prometheus-alertmanager-0   2/2     Running   0          Xm
monitoring-grafana-XXXXXXXXX-XXXXX                       3/3     Running   0          Xm
monitoring-kube-prometheus-operator-XXXXXXXXX-XXXXX      1/1     Running   0          Xm
monitoring-kube-state-metrics-XXXXXXXXX-XXXXX            1/1     Running   0          Xm
monitoring-prometheus-node-exporter-XXXXX                1/1     Running   0          Xm
prometheus-monitoring-kube-prometheus-prometheus-0       2/2     Running   0          Xm
```
