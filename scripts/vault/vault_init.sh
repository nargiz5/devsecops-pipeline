#!/bin/bash
set -e

# Load environment variables
export $(grep -v '^#' ../../.env | xargs)

echo "Cleaning up old Vault containers..."
# Stop and remove any old Vault container
sudo docker rm -f vault 2>/dev/null || true

# Remove old Vault directory if exists
rm -rf ~/vault-docker
mkdir -p ~/vault-docker
cd ~/vault-docker

echo "Deploying HashiCorp Vault container..."
cat <<EOF > docker-compose.yml
version: '3.8'
services:
  vault:
    image: hashicorp/vault:latest
    container_name: vault
    restart: always
    ports:
      - "8200:8200"
    environment:
      - VAULT_DEV_ROOT_TOKEN_ID=${VAULT_TOKEN}
      - VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200
    cap_add:
      - IPC_LOCK
    command: server -dev
EOF

sudo docker compose up -d

echo "Waiting for Vault API to become ready..."
until curl -s ${VAULT_URL}/v1/sys/health | grep -q '"initialized":true'; do
    echo "Vault is booting..."
    sleep 2
done

echo "Vault is running at ${VAULT_URL}"
