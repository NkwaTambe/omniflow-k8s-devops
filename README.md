# OmniFlow K8s DevOps

A comprehensive DevOps pipeline implementation for Kubernetes-based applications, demonstrating industry best practices for CI/CD, infrastructure as code, containerization, and observability.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              OmniFlow DevOps Pipeline                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────────────────┐ │
│  │  Source  │───▶│   CI/CD  │───▶│ Registry │───▶│    Kubernetes Cluster ││
│  │   Code   │    │ Pipeline │    │  (Docker │    │    (Helm Charts)     ││
│  │  (GitHub)│    │(Actions/ │    │   Hub)   │    │                      ││
│  └──────────┘    │ Jenkins) │    └──────────┘    │  ┌────────────────┐  │ │
│                  └──────────┘                     │  │   Workloads    │  │ │
│                        │                          │  └────────────────┘  │ │
│                        ▼                          │  ┌────────────────┐  │ │
│                  ┌──────────┐                     │  │   Monitoring   │  │ │
│                  │Infrastructure│                 │  │(Prometheus/   │  │ │
│                  │    Code     │                  │  │ Grafana/Loki) │  │ │
│                  │ (Terraform) │                  │  └────────────────┘  │ │
│                  └─────────────│                  └──────────────────────┘ │
│                                 │                                          │
│                                 ▼                                          │
│                        ┌──────────────┐                                     │
│                        │ AWS Cloud    │                                     │
│                        │ Infrastructure│                                    │
│                        └──────────────┘                                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Pipeline Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Commit    │────▶│    Build    │────▶│    Test     │────▶│   Deploy    │
│   (Push)    │     │   (Docker)  │     │   (Automated)│    │   (K8s/Helm)│
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────────┘
      │                   │                   │                   │
      │                   │                   │                   │
      ▼                   ▼                   ▼                   ▼
 ┌─────────┐        ┌─────────┐        ┌─────────┐        ┌─────────┐
 │ GitHub  │        │  Image  │        │  Test   │        │Monitor &│
 │ Actions │        │  Build  │        │ Reports │        │ Alerting│
 │ Trigger │        │  & Push │        │         │        │         │
 └─────────┘        └─────────┘        └─────────┘        └─────────┘
```

## Repository Structure

```
omniflow-k8s-devops/
├── .github/
│   └── workflows/          # GitHub Actions CI/CD workflows
├── jenkins/                 # Jenkins pipeline configurations
├── terraform/               # Infrastructure as Code (AWS resources)
├── helm/                    # Kubernetes Helm charts
├── src/                     # Application source code
├── monitoring/              # Prometheus,Grafana,Loki configurations
├── .gitignore               # Git ignore rules└── README.md                # Project documentation
```

## DevOps Components

| Component | Technology | Purpose |
|-----------|------------|---------|
| **Infrastructure** | Terraform | Provision AWS cloud resources (VPC,EKS, etc.) |
| **Containerization** | Docker | Package applications into portable containers |
| **Orchestration** | Kubernetes + Helm | Deploy and manage containerized workloads |
| **CI Pipeline** | GitHub Actions | Automated build, test, and security scanning |
| **CD Pipeline** | Jenkins | Continuous deployment to Kubernetes |
| **Observability** | Prometheus, Grafana, Loki | Monitoring, visualization, and logging |
| **Secrets** | HashiCorp Vault | Secure secrets management |

## Branching Strategy

This project follows **Trunk-Based Development**:

- **`main`** - Production-ready code, always deployable
- **`feature/*`** - Short-lived feature branches (< 2 days)
- **`epic/*`** - Longer-lived epic branches for major features

### Workflow

1. Create a feature branch from `main`
2. Develop and commit changes
3. Open a Pull Request for code review
4. After approval and CI passes, merge to `main`
5. Trigger automatic deployment through CD pipeline

## Getting Started

### Prerequisites

- Docker installed
- kubectl configured
- Helm 3.x installed
- Terraform installed (for infrastructure provisioning)
- Access to AWS account (for deployment)

### Quick Start

```bash
# Clone the repository
git clone https://github.com/NkwaTambe/omniflow-k8s-devops.git
cd omniflow-k8s-devops
```

## License

MIT License - See [LICENSE](LICENSE) for details.

## Contributing

Please read our contributing guidelines before submitting PRs. All contributions must pass CI/CD checks and code review.