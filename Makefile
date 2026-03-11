.PHONY: all \
	start-clusters install-argocd-prod install-argocd-dev \
	wait-argocd-prod wait-argocd-dev \
	port-forward-argocd-prod port-forward-argocd-dev \
	get-password-prod get-password-dev \
	login-prod login-dev \
	deploy-prod deploy-dev \
	sync-prod sync-dev \
	verify cleanup

ARGOCD_PROD_PASSWORD ?= $(shell kubectl --context=production-cluster -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
ARGOCD_DEV_PASSWORD  ?= $(shell kubectl --context=develop-cluster -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

## Run full setup end-to-end
all: start-clusters install-argocd-prod install-argocd-dev wait-argocd-prod wait-argocd-dev deploy-prod deploy-dev sync-prod sync-dev

## 1. Start all 3 minikube clusters
start-clusters:
	minikube start -p production-cluster
	minikube start -p develop-cluster

## 2a. Install ArgoCD on production (prod - manages production + cluster2)
install-argocd-prod:
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply --context=production-cluster -f -
	kubectl apply --context=production-cluster -n argocd --server-side --force-conflicts \
		-f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

## 2b. Install ArgoCD on develop (dev - manages develop)
install-argocd-dev:
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply --context=develop-cluster -f -
	kubectl apply --context=develop-cluster -n argocd --server-side --force-conflicts \
		-f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

## 3a. Wait for ArgoCD prod to be ready
wait-argocd-prod:
	kubectl wait --context=production-cluster --for=condition=ready pod \
		-l app.kubernetes.io/name=argocd-server -n argocd --timeout=180s

## 3b. Wait for ArgoCD dev to be ready
wait-argocd-dev:
	kubectl wait --context=develop-cluster --for=condition=ready pod \
		-l app.kubernetes.io/name=argocd-server -n argocd --timeout=180s

## 4a. Port forward ArgoCD prod UI on :8080 (open a separate terminal)
port-forward-argocd-prod:
	kubectl port-forward --context=production-cluster svc/argocd-server -n argocd 8080:443

## 4b. Port forward ArgoCD dev UI on :8081 (open a separate terminal)
port-forward-argocd-dev:
	kubectl port-forward --context=develop-cluster svc/argocd-server -n argocd 8081:443

## 5a. Print initial admin password (prod)
get-password-prod:
	kubectl --context=production-cluster -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" | base64 -d && echo

## 5b. Print initial admin password (dev)
get-password-dev:
	kubectl --context=develop-cluster -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" | base64 -d && echo

## 6a. Login to ArgoCD prod CLI
login-prod:
	argocd login localhost:8080 --username admin --password $(ARGOCD_PROD_PASSWORD) --insecure

## 6b. Login to ArgoCD dev CLI
login-dev:
	argocd login localhost:8081 --username admin --password $(ARGOCD_DEV_PASSWORD) --insecure

## 7a. Deploy production apps (production: app+app2, cluster2: app3)
deploy-prod:
	argocd app create -f argocd/production-environment/production-cluster/mtl.yaml --upsert \
		--server localhost:8080 --insecure

## 7b. Deploy develop apps (develop: app4)
deploy-dev:
	argocd app create -f argocd/develop-environment/develop-cluster/internal-dso.yaml --upsert \
		--server localhost:8081 --insecure

## 8a. Sync all production apps
sync-prod:
	argocd app sync mtl-tenant    --server localhost:8080 --insecure
	argocd app sync mtl-gateway    --server localhost:8080 --insecure

## 8b. Sync all develop apps
sync-dev:
	argocd app sync internal-dso-tenant --server localhost:8081 --insecure

## 9. Verify all apps
verify:
	@echo "=== Production (argocd-prod :8080) ==="
	argocd app get nginx-app      --server localhost:8080 --insecure
	argocd app get httpd-app      --server localhost:8080 --insecure
	argocd app get nginx-prod-app --server localhost:8080 --insecure
	@echo "=== Develop (argocd-dev :8081) ==="
	argocd app get httpd-dev-app  --server localhost:8081 --insecure

## Port forward nginx (production) -> :8888
port-forward-mtl-tenant:
	kubectl port-forward --context=production-cluster svc/nginx -n nginx-app 8888:80

## Port forward httpd (production) -> :8889
port-forward-mtl-gateway:
	kubectl port-forward --context=production-cluster svc/httpd -n httpd-app 8889:80

## Port forward httpd-dev (develop) -> :8891
port-forward-internal-dso-tenant:
	kubectl port-forward --context=develop-cluster svc/httpd-dev -n httpd-dev-app 8891:80

## Tear everything down
cleanup:
	argocd app delete nginx-app       --server localhost:8080 --insecure --yes || true
	argocd app delete httpd-app       --server localhost:8080 --insecure --yes || true
	argocd app delete httpd-dev-app   --server localhost:8081 --insecure --yes || true
	minikube delete -p production
	minikube delete -p develop
