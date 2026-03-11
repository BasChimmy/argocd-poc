# ArgoCD POC - Multi-Cluster / Multi-Environment Setup

## Overview

Proof of concept for deploying apps across 3 minikube clusters using 2 ArgoCD instances (production + develop).

## Environment Map

| ArgoCD | Port | Cluster | Apps |
|--------|------|---------|------|
| argocd-prod | 8080 | production | app (nginx), app2 (httpd) |
| argocd-prod | 8080 | cluster2 | app3 (nginx-prod) |
| argocd-dev  | 8081 | develop | app4 (httpd-dev) |

## Repository Structure

```
argocd-poc/
├── app/                          # nginx - production (production)
├── app2/                         # httpd - production (production)
├── app3/                         # nginx - production (cluster2)
├── app4/                         # httpd - develop   (develop)
└── argocd/
    ├── production/
    │   ├── production/
    │   │   └── argocd-app.yaml   # app + app2 -> production
    │   └── cluster2/
    │       └── argocd-app3.yaml  # app3 -> cluster2
    └── develop/
        └── develop/
            └── argocd-app4.yaml  # app4 -> develop
```

---

## Prerequisites

| Tool | Install |
|------|---------|
| minikube | `brew install minikube` |
| kubectl | `brew install kubectl` |
| argocd CLI | `brew install argocd` |

---

## Setup Steps

### 1. Start all 3 clusters

```bash
make start-clusters
```

### 2. Install ArgoCD on prod (production) and dev (develop)

```bash
make install-argocd-prod
make install-argocd-dev
make wait-argocd-prod
make wait-argocd-dev
```

### 3. Port forward both ArgoCD UIs (each in a separate terminal)

```bash
make port-forward-argocd-prod   # -> https://localhost:8080
make port-forward-argocd-dev    # -> https://localhost:8081
```

### 4. Get passwords and login

```bash
make get-password-prod
make login-prod

make get-password-dev
make login-dev
```

### 5. Deploy apps

```bash
make deploy-prod   # production: app + app2 | cluster2: app3
make deploy-dev    # develop: app4
```

### 6. Sync

```bash
make sync-prod
make sync-dev
```

### 7. Verify

```bash
make verify
```

---

## Port Forwards for Apps

| Target | Command | URL |
|--------|---------|-----|
| nginx (production) | `make port-forward-nginx` | http://localhost:8888 |
| httpd (production) | `make port-forward-httpd` | http://localhost:8889 |
| nginx-prod (cluster2) | `make port-forward-nginx-prod` | http://localhost:8890 |
| httpd-dev (develop) | `make port-forward-httpd-dev` | http://localhost:8891 |

---

## Teardown

```bash
make cleanup
```

---

## Notes

- argocd-prod (production) also manages cluster2 via the `destination.server` field in the ArgoCD Application manifest — register cluster2 with: `argocd cluster add cluster2 --server localhost:8080 --insecure`
- Update `repoURL` in all ArgoCD manifests under `argocd/` with your actual GitHub repo URL before deploying
- `--upsert` makes `argocd app create -f` idempotent (safe to re-run)
