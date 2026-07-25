# All-in-One Kubernetes - Ambiente n8n

Ambiente autossuficiente de automação baseado em n8n sobre Kubernetes, com suporte a 3 ambientes: **desenvolvimento** (Minikube), **homologação** e **produção**.

## Componentes

| Serviço | Descrição | Porta |
|---------|-----------|-------|
| **n8n Master** | UI e API do n8n | 5678 |
| **n8n Workers** | Workers para processamento de workflows | - |
| **n8n Runners** | Runners para execução isolada de tarefas | - |
| **PostgreSQL 16 + pgvector** | Banco de dados principal | 5432 |
| **Redis 7** | Message broker e cache | 6379 |
| **RabbitMQ** | Message broker | 5672/15672 |
| **MinIO** | Object storage compatível com S3 | 9000/9001 |
| **SigNoz** | Observabilidade (traces, métricas, logs) | 3301 |

## Estrutura

```
.
├── .env.example                    # Template de configuração
├── Makefile                        # Automação de deploy por ambiente
├── scripts/
│   ├── gen-dev-cert.sh             # Geração de certificados para dev
│   └── generate.sh                 # Geração de manifestos a partir do .env
├── kubernetes/
│   ├── base/                       # Recursos comuns (Kustomize base)
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   ├── configmap.yaml
│   │   ├── secrets.yaml
│   │   ├── storage/                # PostgreSQL, Redis, MinIO, RabbitMQ
│   │   ├── n8n/                    # n8n Master, Workers, Runners, OTEL
│   │   └── signoz/                 # SigNoz (ClickHouse, OTel, Query, Frontend)
│   ├── overlays/
│   │   ├── dev/                    # Minikube (nip.io, recursos reduzidos)
│   │   ├── homolog/                # Homologação (domínio homolog, recursos intermediários)
│   │   └── prod/                   # Produção (domínio real, HA, HPA)
│   └── generated/                  # Manifestos gerados pelo generate.sh (gitignored)
```

---

## Desenvolvimento (Minikube)

Ambiente local para desenvolvimento e testes usando Minikube. Todos os testes são executados neste ambiente.

### Pré-requisitos

- Minikube instalado
- kubectl instalado e configurado
- 4 vCPU, 8GB RAM, 40GB disco livre

### Inicialização

```bash
# Iniciar o Minikube
make deploy-dev
```

Isso irá:
1. Gerar manifestos a partir do `.env` via `scripts/generate.sh`
2. Iniciar o Minikube (se não estiver rodando) com `--cpus=4 --memory=8192 --disk-size=40g`
3. Aplicar o overlay Kustomize de dev
4. Aguardar PostgreSQL e Redis ficarem prontos

Para iniciar o Minikube manualmente:
```bash
minikube start --cpus=4 --memory=8192 --disk-size=40g
make deploy-dev
```

### Acesso aos serviços

#### Port-forward individual (recomendado para testes rápidos)

| Serviço | URL (via port-forward) | Comando |
|---------|----------------------|---------|
| n8n | http://localhost:5678 | `make port-forward-n8n` |
| RabbitMQ | http://localhost:15672 | `make port-forward-rabbitmq` |
| MinIO Console | http://localhost:9001 | `make port-forward-minio` |
| SigNoz | http://localhost:3301 | `make port-forward-signoz` |

#### Ingress via nip.io (multiserviço, single port)

Permite acessar todos os serviços pela mesma porta usando hostnames `nip.io`, sem precisar lembrar portas individuais.

**1. Habilitar o ingress controller (executar uma vez por cluster):**
```bash
minikube addons enable ingress
```

**2. Iniciar o port-forward do ingress:**
```bash
# Linux/macOS - portas 80/443 (requer sudo):
# O sudo não herda o KUBECONFIG, passe explicitamente:
sudo KUBECONFIG=$HOME/.kube/config kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 80:80 443:443

# Ou use portas altas (sem sudo):
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80 8443:443
```

**3. Acessar via navegador:**

| Serviço | URL HTTP | URL HTTPS |
|---------|----------|-----------|
| n8n | http://n8n.127.0.0.1.nip.io | https://n8n.127.0.0.1.nip.io |
| RabbitMQ | http://rabbitmq.127.0.0.1.nip.io | https://rabbitmq.127.0.0.1.nip.io |
| MinIO | http://minio.127.0.0.1.nip.io | https://minio.127.0.0.1.nip.io |
| SigNoz | http://signoz.127.0.0.1.nip.io | https://signoz.127.0.0.1.nip.io |

> Com portas altas, adicione a porta na URL: `http://n8n.127.0.0.1.nip.io:8080`

> HTTPS usa certificado autoassinado gerado pelo ingress-nginx. Aceite o aviso de segurança no navegador.

> **Windows**: o port-forward do kubectl funciona normalmente no terminal (PowerShell/CMD). Use portas altas (8080/8443) pois 80/443 podem exigir privilégios de administrador.

### Comandos úteis

```bash
make status              # Status de todos os recursos
make validate            # Validar YAML (dry-run)
make generate            # Gerar manifestos a partir do .env
make logs-n8n            # Logs do n8n master
make logs-n8n-worker     # Logs do n8n worker
make logs-postgres       # Logs do PostgreSQL
make logs-redis          # Logs do Redis
make logs-rabbitmq       # Logs do RabbitMQ
make logs-signoz         # Logs do SigNoz
make teardown-dev        # Remover tudo do ambiente dev
```

### Configuração

Copie e ajuste o `.env`:
```bash
cp .env.example .env
# Definir DEPLOY_ENV=dev
# Definir TLS_ENABLED=false
```

### Certificados TLS (opcional)

Para gerar certificado autoassinado para dev:
```bash
bash scripts/gen-dev-cert.sh
```

### Troubleshooting

| Problema | Solução |
|----------|---------|
| Pods em ImagePullBackOff | Aguardar o download das imagens (primeiro deploy é lento) |
| Minikube sem memória | `minikube delete && minikube start --cpus=4 --memory=8192` |
| Port-forward não funciona | Verificar se o pod está Ready: `kubectl get pods -n all-in-one` |
| Serviço não responde | Aguardar readinessProbe: `kubectl get pods -n all-in-one -w` |

---

## Homologação

Ambiente de pré-produção para validação antes do deploy em produção.

### Pré-requisitos

- Cluster k3s ou Kubernetes com StorageClass default
- kubectl configurado para o cluster
- cert-manager instalado com ClusterIssuer `letsencrypt-staging` (veja seção "Provisionamento do cluster k3s")
- Domínio configurado (ex: `*.homolog.exemplo.com` apontando para o cluster)

> O recurso `Certificate` é provisionado automaticamente via Kustomize. O secret TLS `all-in-one-tls` é criado pelo cert-manager após o deploy.

### Deploy

```bash
# Configurar .env para homolog
# DEPLOY_ENV=homolog
# DOMAIN=exemplo.com
# TLS_ENABLED=true

make deploy-homolog
```

### Acesso

| Serviço | URL |
|---------|-----|
| n8n | https://n8n.homolog.exemplo.com |
| MinIO | https://minio.homolog.exemplo.com |
| SigNoz | https://signoz.homolog.exemplo.com |
| RabbitMQ | https://rabbitmq.homolog.exemplo.com |

### Troubleshooting

| Problema | Solução |
|----------|---------|
| Certificado inválido | cert-manager pode estar usando staging. Aceitar no navegador ou verificar `kubectl get certificate -n all-in-one` |
| Certificado pendente | Verificar status: `kubectl describe certificate all-in-one-tls -n all-in-one` e `kubectl describe certificaterequest -n all-in-one` |
| ClusterIssuer não encontrado | Confirmar se o ClusterIssuer existe: `kubectl get clusterissuer letsencrypt-staging` |

---

## Produção

Ambiente de produção com alta disponibilidade.

### Pré-requisitos

- Cluster k3s ou Kubernetes em cloud com StorageClass default
- kubectl configurado para o cluster
- cert-manager instalado com ClusterIssuer `letsencrypt-production` (veja seção "Provisionamento do cluster k3s")
- Domínio configurado (ex: `*.exemplo.com` apontando para o cluster)
- Mínimo 4 vCPU, 16GB RAM, 100GB disco (ver tabela de requisitos abaixo)

> O recurso `Certificate` é provisionado automaticamente via Kustomize. O secret TLS `all-in-one-tls` é criado pelo cert-manager após o deploy.

### Deploy

```bash
# Configurar .env para produção
# DEPLOY_ENV=prod
# DOMAIN=exemplo.com
# TLS_ENABLED=true

make deploy-prod
```

O overlay de produção inclui:
- **Replicas**: n8n-worker (2), n8n-runner (4)
- **Init containers**: `wait-for-postgres` no master/workers/runners, `wait-for-n8n-master` nos workers/runners
- **Resources**: descomentados por padrão (ver seção "Configurando Resource Limits")
- Domínio: configurado via `.env` (variáveis `N8N_HOST` e `DOMAIN`)

> **Nota**: os resource limits são definidos pelo overlay Kustomize (`DEPLOY_ENV` no `.env`). Cada overlay aplica valores adequados ao ambiente selecionado.

### Acesso

| Serviço | URL |
|---------|-----|
| n8n | https://n8n.exemplo.com |
| MinIO | https://minio.exemplo.com |
| SigNoz | https://signoz.exemplo.com |
| RabbitMQ | https://rabbitmq.exemplo.com |

### Troubleshooting

| Problema | Solução |
|----------|---------|
| Certificado expirado | Verificar cert-manager: `kubectl get certificate -n all-in-one` e `kubectl describe certificaterequest -n all-in-one` |
| Certificado pendente | Verificar logs do cert-manager: `kubectl logs -n cert-manager deployment/cert-manager` |
| Erro de disco | Verificar PVCs: `kubectl get pvc -n all-in-one` |
| Pods em CrashLoopBackOff | Verificar se PostgreSQL está pronto: `kubectl logs -n all-in-one -l component=master` |

---

## Comandos Makefile

| Comando | Descrição |
|---------|-----------|
| `make help` | Lista todos os comandos disponíveis |
| `make generate` | Gera manifestos Kubernetes a partir do `.env` |
| `make deploy-dev` | Deploy no Minikube |
| `make deploy-homolog` | Deploy em homologação |
| `make deploy-prod` | Deploy em produção |
| `make teardown-dev` | Remove ambiente dev |
| `make teardown-homolog` | Remove ambiente homolog |
| `make teardown-prod` | Remove ambiente prod |
| `make status` | Status de todos os recursos |
| `make validate` | Valida manifests (dry-run) |
| `make port-forward-n8n` | n8n em http://localhost:5678 |
| `make port-forward-rabbitmq` | RabbitMQ Management em http://localhost:15672 |
| `make port-forward-minio` | MinIO Console em http://localhost:9001 |
| `make port-forward-signoz` | SigNoz em http://localhost:3301 |
| `make logs-n8n` | Logs do n8n master |
| `make logs-n8n-worker` | Logs do n8n worker |
| `make logs-postgres` | Logs do PostgreSQL |
| `make logs-redis` | Logs do Redis |
| `make logs-rabbitmq` | Logs do RabbitMQ |
| `make logs-signoz` | Logs do SigNoz |

---

## Configurando Resource Limits

Os limits/requests de CPU e memória são definidos pelo overlay Kustomize selecionado via `DEPLOY_ENV` no `.env`. O overlay `dev` aplica recursos reduzidos compatíveis com Minikube; `homolog` e `prod` aplicam recursos progressivamente maiores.

### Onde configurar

| Arquivo | Serviço | Requests (padrão) | Limits (padrão) |
|---------|---------|-------------------|-----------------|
| `kubernetes/base/n8n/master.yaml` | n8n Master | 200m / 256Mi | 1000m / 1Gi |
| `kubernetes/base/n8n/worker.yaml` | n8n Worker | 200m / 256Mi | 1000m / 1Gi |
| `kubernetes/base/n8n/runner.yaml` | n8n Runner | 100m / 128Mi | 500m / 512Mi |
| `kubernetes/base/storage/postgres.yaml` | PostgreSQL | 250m / 256Mi | 1000m / 1Gi |
| `kubernetes/base/storage/redis.yaml` | Redis | 100m / 128Mi | 500m / 512Mi |
| `kubernetes/base/storage/minio.yaml` | MinIO | 100m / 256Mi | 500m / 512Mi |
| `kubernetes/base/storage/rabbitmq.yaml` | RabbitMQ | - | - |
| `kubernetes/base/signoz/signoz.yaml` | SigNoz ClickHouse | 500m / 1Gi | 2000m / 4Gi |
| `kubernetes/base/signoz/signoz.yaml` | SigNoz OTel Collector | 100m / 256Mi | 500m / 512Mi |
| `kubernetes/base/signoz/signoz.yaml` | SigNoz Query Service | 100m / 256Mi | 500m / 512Mi |
| `kubernetes/base/signoz/signoz.yaml` | SigNoz Frontend | 100m / 128Mi | 500m / 256Mi |

### Requisitos mínimos recomendados

| Ambiente | vCPU | RAM | Disco | Descrição |
|----------|------|-----|-------|-----------|
| **Dev** (Minikube) | 4 | 8 GB | 40 GB | Todos os serviços, 1 réplica cada |
| **Homolog** | 4 | 8 GB | 60 GB | Replicas intermediárias |
| **Prod** (mínimo) | 4 | 16 GB | 100 GB | 2 workers, 4 runners |
| **Prod** (recomendado) | 8 | 32 GB | 200 GB | Múltiplos nós, alta disponibilidade |

### Soma total de CPU requests (todos os serviços, 1 réplica)

Sem limits, o Kubernetes não impõe reserva de CPU — os pods competem livremente. Com os limits padrão descomentados:

```
n8n Master   200m
n8n Worker   200m (x2 = 400m em produção)
n8n Runner   100m (x4 = 400m em produção)
PostgreSQL   250m
Redis        100m
MinIO        100m
RabbitMQ      -
SigNoz       800m (ClickHouse 500m + OTel 100m + Query 100m + Frontend 100m)
───────────────────
Total prod  2450m (~2.5 vCPU) — com replicação completa em produção
```

Para ajustar os limites por ambiente, edite o overlay correspondente em `kubernetes/overlays/<env>/kustomization.yaml` ou descomente o bloco `resources:` no base manifest e altere os valores.

### Exemplo: ativar limits para o n8n-worker

No arquivo `kubernetes/base/n8n/worker.yaml`, descomente:

```yaml
resources:
  requests:
    cpu: 200m       # ajuste conforme necessidade
    memory: 256Mi
  limits:
    cpu: 1000m      # ajuste conforme necessidade
    memory: 1Gi
```

---

## Backup

### PostgreSQL
```bash
kubectl exec -n all-in-one deploy/postgres -- pg_dumpall -U postgres > backup.sql
kubectl exec -i -n all-in-one deploy/postgres -- psql -U postgres < backup.sql
```

### Redis
```bash
kubectl exec -n all-in-one deploy/redis -- redis-cli BGSAVE
kubectl cp n8n/redis-xxx:/data/dump.rdb ./redis-backup.rdb
```

### MinIO
```bash
kubectl exec -n all-in-one deploy/minio -- mc mirror /data minio-backup/
```

---

## Provisionamento do cluster k3s em cloud

1. Provisionar VM com Ubuntu 22.04+ (ver tabela de requisitos na seção "Configurando Resource Limits")
2. Instalar k3s:
   ```bash
   curl -sfL https://get.k3s.io | sh -
   ```
3. Copiar kubeconfig:
   ```bash
   sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
   sudo chown $(id -u):$(id -g) ~/.kube/config
   ```
4. Instalar cert-manager (para homolog/prod):
   ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
   ```
5. Criar ClusterIssuer Let's Encrypt staging (homolog):
   ```bash
   kubectl apply -f - <<EOF
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: letsencrypt-staging
   spec:
     acme:
       server: https://acme-staging-v02.api.letsencrypt.org/directory
       email: admin@${DOMAIN}
       privateKeySecretRef:
         name: letsencrypt-staging-account-key
       solvers:
         - http01:
             ingress:
               class: traefik
   EOF
   ```
6. Criar ClusterIssuer Let's Encrypt production (prod):
   ```bash
   kubectl apply -f - <<EOF
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: letsencrypt-production
   spec:
     acme:
       server: https://acme-v02.api.letsencrypt.org/directory
       email: admin@${DOMAIN}
       privateKeySecretRef:
         name: letsencrypt-production-account-key
       solvers:
         - http01:
             ingress:
               class: traefik
   EOF
   ```
7. Verificar:
   ```bash
   kubectl get nodes
   kubectl get storageclass
   ```
8. Seguir instruções de deploy conforme ambiente desejado
