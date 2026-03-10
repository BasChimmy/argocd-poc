.PHONY: all start-minikube install-argocd wait-argocd port-forward-argocd get-password login deploy sync verify port-forward-nginx port-forward-httpd cleanup

ARGOCD_PASSWORD ?= $(shell argocd admin initial-password -n argocd 2>/dev/null | head -1)

## Run full setup end-to-end (excluding port-forwards and login which require interaction)
all: start-minikube install-argocd wait-argocd deploy sync

## 1. Start minikube
start-minikube:
	minikube start

## 2. Install ArgoCD
install-argocd:
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

## 2b. Wait for ArgoCD server to be ready
wait-argocd:
	kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=120s

## 3a. Port forward ArgoCD UI (runs in foreground — open a separate terminal)
port-forward-argocd:
	kubectl port-forward svc/argocd-server -n argocd 8080:443

## 3b. Print initial admin password
get-password:
	argocd admin initial-password -n argocd

## 3c. Login to ArgoCD CLI (prompts for password if not set via ARGOCD_PASSWORD env var)
login:
	argocd login localhost:8080 --username admin --password $(ARGOCD_PASSWORD) --insecure

## 4. Apply ArgoCD Application manifests with upsert (nginx + httpd)
deploy:
	argocd app create -f argocd/argocd-nginx-app.yaml --upsert

## 5. Sync both applications
sync:
	argocd app sync nginx-app
	argocd app sync httpd-app

## 6a. Verify ArgoCD app status and pods (nginx)
verify:
	argocd app get nginx-app
	kubectl get pods -n nginx-app

## 6b. Verify ArgoCD app status and pods (httpd)
verify-httpd:
	argocd app get httpd-app
	kubectl get pods -n httpd-app

## 7a. Port forward nginx (runs in foreground — open a separate terminal, then visit http://localhost:8888)
port-forward-nginx:
	kubectl port-forward svc/nginx -n nginx-app 8888:80

## 7b. Port forward httpd (runs in foreground — open a separate terminal, then visit http://localhost:8889)
port-forward-httpd:
	kubectl port-forward svc/httpd -n httpd-app 8889:80

## Tear everything down
cleanup:
	argocd app delete nginx-app --yes || true
	argocd app delete httpd-app --yes || true
	kubectl delete namespace nginx-app --ignore-not-found
	kubectl delete namespace httpd-app --ignore-not-found
	kubectl delete namespace argocd --ignore-not-found
	minikube stop
