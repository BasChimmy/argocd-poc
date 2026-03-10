# ArgoCD POC - Local Machine Setup with Minikube

## Overview

Proof of concept for deploying a basic nginx app using ArgoCD `app create -f` command with `--upsert` flag on a local minikube cluster.

## Goals

- Deploy ArgoCD on local minikube
- Create an ArgoCD Application using a YAML manifest via CLI (`argocd app create -f`)
- Demonstrate `--upsert` behavior (create if not exists, update if already exists)
- Deploy a simple nginx app as the target application

---

## Repository Structure

```
argocd-poc/
├── README.md
├── app/
│   ├── deployment.yaml
│   └── service.yaml
└── argocd/
    └── argocd-nginx-app.yaml
```

---

## File Contents

### `app/deployment.yaml`

A simple nginx Deployment with 1 replica.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:latest
          ports:
            - containerPort: 80
```

### `app/service.yaml`

A ClusterIP Service exposing nginx on port 80.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
  type: ClusterIP
```

### `argocd/argocd-nginx-app.yaml`

ArgoCD Application manifest pointing to this repo.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<your-username>/argocd-poc  # replace with actual repo URL
    targetRevision: HEAD
    path: app
  destination:
    server: https://kubernetes.default.svc
    namespace: nginx-app
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
```

---

## Prerequisites

Install the following tools on your local machine:

| Tool | Purpose | Install |
|------|---------|---------|
| minikube | Local Kubernetes cluster | `brew install minikube` |
| kubectl | Kubernetes CLI | `brew install kubectl` |
| argocd CLI | ArgoCD CLI | `brew install argocd` |
| yq | YAML processor (optional) | `brew install yq` |

> For Windows, replace `brew install` with `choco install`.

---

## Setup Steps

### 1. Start Minikube

```bash
minikube start
```

### 2. Install ArgoCD

```bash
kubectl create namespace argocd

kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD server to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=120s
```

### 3. Access ArgoCD

```bash
# Port forward ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get initial admin password
argocd admin initial-password -n argocd

# Login via CLI
argocd login localhost:8080 --username admin --password <password> --insecure
```

### 4. Apply ArgoCD Application via CLI

```bash
argocd app create -f argocd/argocd-nginx-app.yaml --upsert
```

> `--upsert` means: create if not exists, update if already exists. Safe to run multiple times.

### 5. Sync the Application

```bash
argocd app sync nginx-app
```

### 6. Verify Deployment

```bash
# Check ArgoCD app status
argocd app get nginx-app

# Check pods in target namespace
kubectl get pods -n nginx-app

# Port forward to test nginx
kubectl port-forward svc/nginx -n nginx-app 8888:80
# Open http://localhost:8888
```

---

## Expected Behavior

| Step | Expected Result |
|------|----------------|
| `argocd app create -f ... --upsert` | App `nginx-app` created in ArgoCD |
| `argocd app sync nginx-app` | nginx Deployment and Service created in `nginx-app` namespace |
| `kubectl get pods -n nginx-app` | 1 nginx pod running |
| `curl http://localhost:8888` | nginx welcome page returned |

---

## Notes

- `argocd app create -f` only supports `kind: Application` or `kind: ApplicationSet` — not generic Kubernetes resources
- For multi-document YAML files (separated by `---`), split into individual files first before using `argocd app create -f`
- `project: default` and `server: https://kubernetes.default.svc` are used here since this is a local minikube cluster with no custom ArgoCD projects
