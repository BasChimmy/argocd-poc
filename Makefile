.PHONY: all \
	start-clusters install-argocd-prod install-argocd-dev \
	wait-argocd-prod wait-argocd-dev \
	port-forward-argocd-prod port-forward-argocd-dev \
	get-password-prod get-password-dev \
	login-prod login-dev \
	deploy-prod deploy-dev \
	sync-prod sync-dev \
	verify cleanup

ARGOCD_PROD_PASSWORD ?= $(shell KUBECONFIG=~/.kube/cluster1 argocd admin initial-password -n argocd 2>/dev/null | head -1)
ARGOCD_DEV_PASSWORD  ?= $(shell KUBECONFIG=~/.kube/cluster3 argocd admin initial-password -n argocd 2>/dev/null | head -1)

## Run full setup end-to-end
all: start-clusters install-argocd-prod install-argocd-dev wait-argocd-prod wait-argocd-dev deploy-prod deploy-dev sync-prod sync-dev

## 1. Start all 3 minikube clusters
start-clusters:
	minikube start -p cluster1
	minikube start -p cluster2
	minikube start -p cluster3

## 2a. Install ArgoCD on cluster1 (prod - manages cluster1 + cluster2)
install-argocd-prod:
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply --context=cluster1 -f -
	kubectl apply --context=cluster1 -n argocd --server-side --force-conflicts \
		-f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

## 2b. Install ArgoCD on cluster3 (dev - manages cluster3)
install-argocd-dev:
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply --context=cluster3 -f -
	kubectl apply --context=cluster3 -n argocd --server-side --force-conflicts \
		-f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

## 3a. Wait for ArgoCD prod to be ready
wait-argocd-prod:
	kubectl wait --context=cluster1 --for=condition=ready pod \
		-l app.kubernetes.io/name=argocd-server -n argocd --timeout=180s

## 3b. Wait for ArgoCD dev to be ready
wait-argocd-dev:
	kubectl wait --context=cluster3 --for=condition=ready pod \
		-l app.kubernetes.io/name=argocd-server -n argocd --timeout=180s

## 4a. Port forward ArgoCD prod UI on :8080 (open a separate terminal)
port-forward-argocd-prod:
	kubectl port-forward --context=cluster1 svc/argocd-server -n argocd 8080:443

## 4b. Port forward ArgoCD dev UI on :8081 (open a separate terminal)
port-forward-argocd-dev:
	kubectl port-forward --context=cluster3 svc/argocd-server -n argocd 8081:443

## 5a. Print initial admin password (prod)
get-password-prod:
	kubectl --context=cluster1 -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" | base64 -d && echo

## 5b. Print initial admin password (dev)
get-password-dev:
	kubectl --context=cluster3 -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" | base64 -d && echo

## 6a. Login to ArgoCD prod CLI
login-prod:
	argocd login localhost:8080 --username admin --password $(ARGOCD_PROD_PASSWORD) --insecure

## 6b. Login to ArgoCD dev CLI
login-dev:
	argocd login localhost:8081 --username admin --password $(ARGOCD_DEV_PASSWORD) --insecure

## 7a. Deploy production apps (cluster1: app+app2, cluster2: app3)
deploy-prod:
	argocd app create -f argocd/production/cluster1/argocd-app.yaml --upsert \
		--server localhost:8080 --insecure
	argocd app create -f argocd/production/cluster2/argocd-app3.yaml --upsert \
		--server localhost:8080 --insecure

## 7b. Deploy develop apps (cluster3: app4)
deploy-dev:
	argocd app create -f argocd/develop/cluster3/argocd-app4.yaml --upsert \
		--server localhost:8081 --insecure

## 8a. Sync all production apps
sync-prod:
	argocd app sync nginx-app    --server localhost:8080 --insecure
	argocd app sync httpd-app    --server localhost:8080 --insecure
	argocd app sync nginx-prod-app --server localhost:8080 --insecure

## 8b. Sync all develop apps
sync-dev:
	argocd app sync httpd-dev-app --server localhost:8081 --insecure

## 9. Verify all apps
verify:
	@echo "=== Production (argocd-prod :8080) ==="
	argocd app get nginx-app      --server localhost:8080 --insecure
	argocd app get httpd-app      --server localhost:8080 --insecure
	argocd app get nginx-prod-app --server localhost:8080 --insecure
	@echo "=== Develop (argocd-dev :8081) ==="
	argocd app get httpd-dev-app  --server localhost:8081 --insecure

## Port forward nginx (cluster1) -> :8888
port-forward-nginx:
	kubectl port-forward --context=cluster1 svc/nginx -n nginx-app 8888:80

## Port forward httpd (cluster1) -> :8889
port-forward-httpd:
	kubectl port-forward --context=cluster1 svc/httpd -n httpd-app 8889:80

## Port forward nginx-prod (cluster2) -> :8890
port-forward-nginx-prod:
	kubectl port-forward --context=cluster2 svc/nginx-prod -n nginx-prod-app 8890:80

## Port forward httpd-dev (cluster3) -> :8891
port-forward-httpd-dev:
	kubectl port-forward --context=cluster3 svc/httpd-dev -n httpd-dev-app 8891:80

## Tear everything down
cleanup:
	argocd app delete nginx-app       --server localhost:8080 --insecure --yes || true
	argocd app delete httpd-app       --server localhost:8080 --insecure --yes || true
	argocd app delete nginx-prod-app  --server localhost:8080 --insecure --yes || true
	argocd app delete httpd-dev-app   --server localhost:8081 --insecure --yes || true
	minikube stop -p cluster1
	minikube stop -p cluster2
	minikube stop -p cluster3
