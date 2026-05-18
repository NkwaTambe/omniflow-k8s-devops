# CI/CD Workflow Documentation

This document explains the CI/CD pipelines configured for the OmniFlow K8s DevOps project.

## Overview

The project uses two main GitHub Actions workflows:
- **CI Pipeline** (`.github/workflows/ci.yml`) - Builds, tests, and deploys the application
- **Security Pipeline** (`.github/workflows/security.yml`) - Security scanning and vulnerability detection

---

## CI Pipeline

### Triggers

```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
```

The pipeline runs:
- **On Pull Requests:** When someone opens or updates a PR targeting `main`
- **On Push to main:** When code is merged to the `main` branch

---

### Jobs

#### 1. Lint & Static Analysis

**When:** Pull Requests AND Push to main

**Purpose:** Catch code quality issues early before they reach the main branch.

**Steps:**
1. Checkout code
2. Setup Node.js 20
3. Install dependencies (`npm ci`)
4. Run ESLint - checks for code style and potential errors
5. TypeScript type check (`tsc --noEmit`) - catches type errors without building

**Why needed:** Prevents buggy code from being merged. Linting ensures consistent code style across the team, while TypeScript checks catch type-related bugs at compile time instead of runtime.

---

#### 2. Unit Tests

**When:** Pull Requests AND Push to main

**Purpose:** Verify application logic works correctly.

**Steps:**
1. Checkout code
2. Setup Node.js 20
3. Install dependencies
4. Run Vitest with coverage
5. Upload coverage report as artifact

**Why needed:** Tests are the foundation of CI/CD. They ensure new changes don't break existing functionality. Code coverage helps identify untested code paths.

---

#### 3. Security Scanning (Trivy Filesystem)

**When:** Pull Requests AND Push to main

**Purpose:** Detect vulnerabilities in dependencies and configuration files.

**Steps:**
1. Checkout code
2. Run Trivy in filesystem mode - scans all files for vulnerabilities
3. Upload SARIF results to GitHub Security tab
4. Run Trivy in config mode - checks for misconfigurations in Docker, Kubernetes, Terraform files

**Why needed:** Shift-left security - catch vulnerabilities early before they reach production. The filesystem scan checks dependency vulnerabilities, while config scan detects Dockerfile misconfigurations (like running as root user).

---

#### 4. Build and Scan Container Image

**When:** Pull Requests AND Push to main

**Behavior differs based on trigger:**

| Trigger | Build | Push to Registry | Platforms | Scan |
|---------|-------|------------------|-----------|------|
| Pull Request | ✅ Yes | ❌ No | linux/amd64 only | Local image |
| Merge to main | ✅ Yes | ✅ Yes | linux/amd64, linux/arm64 | Registry image |

**Purpose:** Create and scan a container image for deployment.

**Why build and scan in the same job?**

The image must exist on the same runner where Trivy runs. When we build with `load: true` (for PRs), the image is only available locally in that job's runner. Scanning must happen in the same job to access the local image.

**Steps:**
1. Checkout code
2. Setup Docker Buildx for multi-platform builds
3. Login to GitHub Container Registry (only on merge to main)
4. Extract metadata for Docker tags
5. Build image (always)
6. Push image (only on merge to main)
7. Run Trivy on the built image
8. Upload SARIF results to GitHub Security tab

---

## Security Pipeline

### Triggers

```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 0 * * 0'  # Every Sunday at midnight
```

Scheduled runs ensure we catch new vulnerabilities discovered after code was written.

---

### Jobs

#### 1. Dependency Check

**When:** Pull Requests AND Push to main

**Purpose:** Audit npm packages for known vulnerabilities.

**Steps:**
1. Run `npm audit --audit-level=high`
2. Run `npm audit fix --dry-run` (shows what would be fixed)

**Why needed:** Dependencies can have vulnerabilities discovered after installation. This catches issues like Log4j-style vulnerabilities.

---

#### 2. Generate SBOM

**When:** Pull Requests AND Push to main

**Purpose:** Create a Software Bill of Materials.

**What is SBOM?** A complete list of all components (including transitive dependencies) in the software. Required for compliance (SBOM mandates in US) and helps track vulnerable components.

**Output:** `sbom.spdx.json` artifact uploaded to GitHub

---

#### 3. CodeQL Analysis

**When:** Pull Requests AND Push to main

**Purpose:** Deep static analysis for security vulnerabilities.

**Why needed:** While ESLint catches code style issues, CodeQL performs deep semantic analysis to find:
- SQL injection
- XSS vulnerabilities
- Path traversal
- And more security-specific issues

---

## Summary: When Jobs Run

| Job | Pull Request | Merge to Main | Purpose |
|-----|:------------:|:-------------:|---------|
| Lint | ✅ | ✅ | Catch code issues before merge |
| Test | ✅ | ✅ | Verify functionality before merge |
| Security Scan (fs) | ✅ | ✅ | Find vulnerabilities before merge |
| Build + Scan Image | ✅ (build only) | ✅ (build + push) | Verify build works, scan for vulnerabilities |
| Dependency Check | ✅ | ✅ | Audit dependencies before merge |
| SBOM | ✅ | ✅ | Track components before merge |
| CodeQL | ✅ | ✅ | Find security issues before merge |

**Key principle:** All quality gates run on Pull Requests to catch issues **before** they reach main branch.

---

## Key Decisions

### Why GitHub Container Registry (ghcr.io)?

1. Integrated with GitHub - no separate credentials needed
2. Uses `GITHUB_TOKEN` automatically provided to Actions
3. Free for public repositories
4. Easy access control via GitHub permissions

### Why Multi-stage Dockerfile?

1. Smaller production image (nginx alpine vs node + build tools)
2. Security - no build tools in production
3. Faster deployments

### Why Non-root User in Dockerfile?

1. Trivy security check (DS-0002)
2. Best practice - if container is compromised, attacker doesn't have root
3. Many Kubernetes security policies require non-root containers

### Why Only Push on Merge to Main?

1. Registry cleanliness - no half-finished PR images
2. Image tags like `latest` always point to production-ready code
3. Reduces storage costs
4. Clear deployment pipeline: PR → Review → Merge → Build & Push → Deploy

---

## Configuration Reference

### Permissions

```yaml
permissions:
  contents: read        # Read repository contents
  packages: write       # Push to GitHub Packages (ghcr.io)
  security-events: write  # Upload SARIF to Security tab
```

### Environment Variables

```yaml
env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}
```

### Multi-platform Support

```yaml
platforms: linux/amd64,linux/arm64
```

Supports both traditional x86 servers and modern ARM infrastructure.

---

## Useful Commands

### Local Testing

```bash
# Run linting
cd src && npm run lint

# Run tests with coverage
cd src && npm run test:coverage

# Build Docker image locally
docker build -t omniflow-frontend ./src

# Run Trivy locally
trivy fs .
trivy config .
```

### View Results

- **CI Status:** GitHub Actions tab → CI Pipeline
- **Security Findings:** Security tab → Code scanning alerts
- **Images:** Packages tab → Container registry
- **SBOM:** Artifacts in workflow run