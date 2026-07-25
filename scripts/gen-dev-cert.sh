#!/bin/bash
# Gera certificado autoassinado para ambiente de desenvolvimento (Minikube)
# Uso: bash scripts/gen-dev-cert.sh

set -e

CERT_DIR="kubernetes/overlays/dev"
CERT_NAME="tls-dev"

mkdir -p "${CERT_DIR}"

# Gerar chave privada e certificado autoassinado
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "${CERT_DIR}/${CERT_NAME}.key" \
  -out "${CERT_DIR}/${CERT_NAME}.crt" \
  -subj "/CN=*.127.0.0.1.nip.io/O=Local Development/C=BR" \
  -addext "subjectAltName=DNS:*.127.0.0.1.nip.io,DNS:*.all-in-one.svc.cluster.local"

echo "Certificado autoassinado gerado em ${CERT_DIR}/${CERT_NAME}.{key,crt}"

# Criar Secret TLS no Kubernetes (se cluster existir)
if kubectl cluster-info &>/dev/null; then
  kubectl create secret tls "${CERT_NAME}" \
    --key="${CERT_DIR}/${CERT_NAME}.key" \
    --cert="${CERT_DIR}/${CERT_NAME}.crt" \
    -n all-in-one --dry-run=client -o yaml > "${CERT_DIR}/${CERT_NAME}-secret.yaml"
  echo "Secret TLS gerado em ${CERT_DIR}/${CERT_NAME}-secret.yaml"
else
  echo "Cluster Kubernetes não detectado. Secret TLS não foi criado."
fi
