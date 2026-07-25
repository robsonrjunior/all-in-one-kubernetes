.PHONY: help generate deploy deploy-dev deploy-homolog deploy-prod teardown-dev teardown-homolog teardown-prod status validate port-forward-n8n port-forward-rabbitmq port-forward-minio port-forward-signoz logs-n8n logs-n8n-worker logs-postgres logs-redis logs-rabbitmq logs-signoz

NAMESPACE ?= all-in-one
.DEFAULT_GOAL := help

help: ## Exibe esta ajuda
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

# ============================================
# Geração de manifestos
# ============================================

generate: ## Gera manifestos Kubernetes a partir do .env
	@bash scripts/generate.sh

# ============================================
# Deploy
# ============================================

deploy: ## Deploy no ambiente definido por DEPLOY_ENV no .env
	@if [ ! -f .env ]; then echo "ERRO: .env nao encontrado. Execute: cp .env.example .env"; exit 1; fi
	@eval "$$(grep -E '^DEPLOY_ENV=' .env)" && \
		case "$$DEPLOY_ENV" in \
			dev)     $(MAKE) deploy-dev ;; \
			homolog) $(MAKE) deploy-homolog ;; \
			prod)    $(MAKE) deploy-prod ;; \
			*)       echo "ERRO: DEPLOY_ENV invalido '$$DEPLOY_ENV'. Use: dev, homolog ou prod."; exit 1 ;; \
		esac

deploy-dev: ## Deploy no Minikube (desenvolvimento)
	@echo ">>> Gerando manifestos..."
	@bash scripts/generate.sh dev
	@echo ">>> Verificando Minikube..."
	@minikube status 2>/dev/null || (echo "Iniciando Minikube..." && minikube start --cpus=4 --memory=8192 --disk-size=40g)
	@echo ">>> Aplicando overlay dev..."
	kubectl apply -f kubernetes/generated/dev.yaml
	@echo ">>> Aguardando pods..."
	kubectl wait --for=condition=ready pod -l app=postgres -n $(NAMESPACE) --timeout=120s || true
	kubectl wait --for=condition=ready pod -l app=redis -n $(NAMESPACE) --timeout=60s || true
	@echo ">>> Deploy dev concluido. Use 'make status' para verificar."

deploy-homolog: ## Deploy no ambiente de homologacao
	@echo ">>> Gerando manifestos..."
	@bash scripts/generate.sh homolog
	@echo ">>> Aplicando overlay homolog..."
	kubectl apply -f kubernetes/generated/homolog.yaml
	@echo ">>> Aguardando rollouts..."
	kubectl rollout status deployment/n8n-master -n $(NAMESPACE) --timeout=120s || true
	@echo ">>> Deploy homolog concluido."

deploy-prod: ## Deploy no ambiente de producao
	@echo ">>> Gerando manifestos..."
	@bash scripts/generate.sh prod
	@echo ">>> ATENCAO: deploy de producao!"
	@echo ">>> Aplicando overlay prod..."
	kubectl apply -f kubernetes/generated/prod.yaml
	@echo ">>> Aguardando rollouts..."
	kubectl rollout status deployment/n8n-master -n $(NAMESPACE) --timeout=120s || true
	kubectl rollout status deployment/n8n-worker -n $(NAMESPACE) --timeout=120s || true
	@echo ">>> Deploy prod concluido."

# ============================================
# Teardown
# ============================================

teardown-dev: ## Remove todos os recursos do ambiente dev
	@echo ">>> Removendo overlay dev..."
	kubectl delete -k kubernetes/overlays/dev/ --ignore-not-found
	@echo ">>> Teardown dev concluido."

teardown-homolog: ## Remove todos os recursos do ambiente de homologacao
	@echo ">>> ATENCAO: removendo ambiente de homologacao!"
	kubectl delete -k kubernetes/overlays/homolog/ --ignore-not-found

teardown-prod: ## Remove todos os recursos do ambiente de producao
	@echo ">>> PERIGO: removendo ambiente de producao!"
	kubectl delete -k kubernetes/overlays/prod/ --ignore-not-found

# ============================================
# Status
# ============================================

status: ## Exibe status de todos os recursos no namespace
	@echo "=== Pods ==="
	kubectl get pods -n $(NAMESPACE) -o wide
	@echo ""
	@echo "=== Services ==="
	kubectl get svc -n $(NAMESPACE)
	@echo ""
	@echo "=== Ingresses ==="
	kubectl get ingress -n $(NAMESPACE)
	@echo ""
	@echo "=== PVCs ==="
	kubectl get pvc -n $(NAMESPACE)
	@echo ""
	@echo "=== HPAs ==="
	kubectl get hpa -n $(NAMESPACE) 2>/dev/null || echo "Nenhum HPA configurado"

# ============================================
# Validação
# ============================================

validate: ## Valida os manifests Kustomize (dry-run)
	@echo ">>> Validando overlay dev..."
	kubectl kustomize kubernetes/overlays/dev/ > /dev/null && echo "  dev: OK" || echo "  dev: ERRO"
	@echo ">>> Validando overlay homolog..."
	kubectl kustomize kubernetes/overlays/homolog/ > /dev/null && echo "  homolog: OK" || echo "  homolog: ERRO"
	@echo ">>> Validando overlay prod..."
	kubectl kustomize kubernetes/overlays/prod/ > /dev/null && echo "  prod: OK" || echo "  prod: ERRO"
	@echo ">>> Gerando manifestos e validando..."
	@bash scripts/generate.sh 2>/dev/null || echo "  generate: ERRO (verifique seu .env)"
	@echo ">>> Validando dry-run dev..."
	kubectl apply -f kubernetes/generated/dev.yaml --dry-run=client > /dev/null && echo "  dry-run dev: OK" || echo "  dry-run dev: ERRO"

# ============================================
# Port Forward
# ============================================

port-forward-n8n: ## Encaminha porta do n8n para localhost:5678
	kubectl port-forward -n $(NAMESPACE) svc/n8n-master 5678:5678

port-forward-rabbitmq: ## Encaminha porta do RabbitMQ management para localhost:15672
	kubectl port-forward -n $(NAMESPACE) svc/rabbitmq 15672:15672

port-forward-minio: ## Encaminha porta do MinIO Console para localhost:9001
	kubectl port-forward -n $(NAMESPACE) svc/minio 9001:9001

port-forward-signoz: ## Encaminha porta do SigNoz para localhost:3301
	kubectl port-forward -n $(NAMESPACE) svc/signoz-frontend 3301:3301

# ============================================
# Logs
# ============================================

logs-n8n: ## Exibe logs do n8n-master
	kubectl logs -f -n $(NAMESPACE) deployment/n8n-master

logs-n8n-worker: ## Exibe logs do n8n-worker
	kubectl logs -f -n $(NAMESPACE) deployment/n8n-worker

logs-postgres: ## Exibe logs do PostgreSQL
	kubectl logs -f -n $(NAMESPACE) statefulset/postgres

logs-redis: ## Exibe logs do Redis
	kubectl logs -f -n $(NAMESPACE) deployment/redis

logs-rabbitmq: ## Exibe logs do RabbitMQ
	kubectl logs -f -n $(NAMESPACE) deployment/rabbitmq

logs-signoz: ## Exibe logs do SigNoz frontend
	kubectl logs -f -n $(NAMESPACE) deployment/signoz-frontend
