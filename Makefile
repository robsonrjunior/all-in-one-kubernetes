.PHONY: help generate deploy deploy-dev deploy-homolog deploy-prod teardown-dev teardown-homolog teardown-prod status validate port-forward-n8n port-forward-rabbitmq port-forward-minio port-forward-pgadmin port-forward-redisinsight logs-n8n logs-n8n-worker logs-n8n-runner logs-postgres logs-redis logs-rabbitmq

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
	@minikube status 2>/dev/null || (echo "Iniciando Minikube..." && minikube start --driver=docker --cpus=4 --memory=8192 --disk-size=40g)
	@echo ">>> Fase 1: Infraestrutura (PostgreSQL + Redis)..."
	kubectl apply -f kubernetes/generated/dev-infra.yaml
	@echo ">>> Aguardando PostgreSQL..."
	kubectl wait --for=condition=ready pod -l app=postgres -n $(NAMESPACE) --timeout=120s || true
	@echo ">>> Aguardando Redis..."
	kubectl wait --for=condition=ready pod -l app=redis -n $(NAMESPACE) --timeout=60s || true
	@echo ">>> Fase 2: Servicos..."
	kubectl apply -f kubernetes/generated/dev.yaml
	kubectl rollout restart deployment/n8n-master deployment/n8n-worker -n $(NAMESPACE)
	@echo ">>> Aguardando n8n-master..."
	kubectl wait --for=condition=ready pod -l app=n8n,component=master -n $(NAMESPACE) --timeout=120s || true
	@echo ">>> Aguardando n8n-runner..."
	kubectl rollout status deployment/n8n-runner -n $(NAMESPACE) --timeout=120s || true
	@echo ">>> Deploy dev concluido. Use 'make status' para verificar."

deploy-homolog: ## Deploy no ambiente de homologacao
	@echo ">>> Gerando manifestos..."
	@bash scripts/generate.sh homolog
	@echo ">>> Fase 1: Infraestrutura (PostgreSQL + Redis)..."
	kubectl apply -f kubernetes/generated/homolog-infra.yaml
	@echo ">>> Aguardando PostgreSQL..."
	kubectl wait --for=condition=ready pod -l app=postgres -n $(NAMESPACE) --timeout=120s || true
	@echo ">>> Aguardando Redis..."
	kubectl wait --for=condition=ready pod -l app=redis -n $(NAMESPACE) --timeout=60s || true
	@echo ">>> Fase 2: Servicos..."
	kubectl apply -f kubernetes/generated/homolog.yaml
	kubectl rollout restart deployment/n8n-master deployment/n8n-worker -n $(NAMESPACE)
	@echo ">>> Aguardando rollouts..."
	kubectl rollout status deployment/n8n-master -n $(NAMESPACE) --timeout=120s || true
	kubectl rollout status deployment/n8n-runner -n $(NAMESPACE) --timeout=120s || true
	@echo ">>> Deploy homolog concluido."

deploy-prod: ## Deploy no ambiente de producao
	@echo ">>> Gerando manifestos..."
	@bash scripts/generate.sh prod
	@echo ">>> ATENCAO: deploy de producao!"
	@echo ">>> Fase 1: Infraestrutura (PostgreSQL + Redis)..."
	kubectl apply -f kubernetes/generated/prod-infra.yaml
	@echo ">>> Aguardando PostgreSQL..."
	kubectl wait --for=condition=ready pod -l app=postgres -n $(NAMESPACE) --timeout=120s || true
	@echo ">>> Aguardando Redis..."
	kubectl wait --for=condition=ready pod -l app=redis -n $(NAMESPACE) --timeout=60s || true
	@echo ">>> Fase 2: Servicos..."
	kubectl apply -f kubernetes/generated/prod.yaml
	kubectl rollout restart deployment/n8n-master deployment/n8n-worker -n $(NAMESPACE)
	@echo ">>> Aguardando rollouts..."
	kubectl rollout status deployment/n8n-master -n $(NAMESPACE) --timeout=120s || true
	kubectl rollout status deployment/n8n-worker -n $(NAMESPACE) --timeout=120s || true
	kubectl rollout status deployment/n8n-runner -n $(NAMESPACE) --timeout=120s || true
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
	@echo ">>> Validando overlay infra dev..."
	kubectl kustomize --load-restrictor LoadRestrictionsNone kubernetes/overlays/dev/infra/ > /dev/null && echo "  dev/infra: OK" || echo "  dev/infra: ERRO"
	@echo ">>> Validando overlay infra homolog..."
	kubectl kustomize --load-restrictor LoadRestrictionsNone kubernetes/overlays/homolog/infra/ > /dev/null && echo "  homolog/infra: OK" || echo "  homolog/infra: ERRO"
	@echo ">>> Validando overlay infra prod..."
	kubectl kustomize --load-restrictor LoadRestrictionsNone kubernetes/overlays/prod/infra/ > /dev/null && echo "  prod/infra: OK" || echo "  prod/infra: ERRO"
	@echo ">>> Gerando manifestos e validando..."
	@bash scripts/generate.sh 2>/dev/null || echo "  generate: ERRO (verifique seu .env)"
	@echo ">>> Validando dry-run dev..."
	kubectl apply -f kubernetes/generated/dev.yaml --dry-run=client > /dev/null && echo "  dry-run dev: OK" || echo "  dry-run dev: ERRO"
	@echo ">>> Validando dry-run dev infra..."
	kubectl apply -f kubernetes/generated/dev-infra.yaml --dry-run=client > /dev/null && echo "  dry-run dev-infra: OK" || echo "  dry-run dev-infra: ERRO"

# ============================================
# Port Forward
# ============================================

port-forward-n8n: ## Encaminha porta do n8n para localhost:5678
	kubectl port-forward -n $(NAMESPACE) svc/n8n-master 5678:5678

port-forward-rabbitmq: ## Encaminha porta do RabbitMQ management para localhost:15672
	kubectl port-forward -n $(NAMESPACE) svc/rabbitmq 15672:15672

port-forward-minio: ## Encaminha porta do MinIO Console para localhost:9001
	kubectl port-forward -n $(NAMESPACE) svc/minio 9001:9001

port-forward-pgadmin: ## Encaminha porta do pgAdmin para localhost:8080
	kubectl port-forward -n $(NAMESPACE) svc/pgadmin 8080:80

port-forward-redisinsight: ## Encaminha porta do RedisInsight para localhost:5540
	kubectl port-forward -n $(NAMESPACE) svc/redisinsight 5540:5540

# ============================================
# Logs
# ============================================

logs-n8n: ## Exibe logs do n8n-master
	kubectl logs -f -n $(NAMESPACE) deployment/n8n-master

logs-n8n-worker: ## Exibe logs do n8n-worker
	kubectl logs -f -n $(NAMESPACE) deployment/n8n-worker

logs-n8n-runner: ## Exibe logs do n8n-runner
	kubectl logs -f -n $(NAMESPACE) deployment/n8n-runner

logs-postgres: ## Exibe logs do PostgreSQL
	kubectl logs -f -n $(NAMESPACE) statefulset/postgres

logs-redis: ## Exibe logs do Redis
	kubectl logs -f -n $(NAMESPACE) deployment/redis

logs-rabbitmq: ## Exibe logs do RabbitMQ
	kubectl logs -f -n $(NAMESPACE) deployment/rabbitmq


