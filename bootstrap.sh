#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)

echo "=== Step 0: Prepare OS & Docker ==="
bash scripts/setup/install_dependencies.sh
bash scripts/setup/install_docker.sh
bash scripts/setup/insecure_reg.sh

echo "=== Step 1: Cleanup old containers ==="
bash scripts/setup/cleanup_project.sh

sudo docker compose up --no-start
sudo docker network inspect devsecops-net >/dev/null 2>&1 || \
    sudo docker network create devsecops-net
echo "=== Step 2: Vault ==="
# Start Vault via master docker-compose

sudo -E docker compose --env-file .env up -d vault
# Wait for Vault API
until curl -s ${VAULT_URL}/v1/sys/health | grep -q '"initialized":true'; do
    echo "Vault booting..."
    sleep 2
done
echo "Vault is ready!"
bash scripts/vault/vault_inject.sh

echo "=== Step 3: GitLab ==="
sudo -E docker compose --env-file .env up -d gitlab gitlab-runner
# Wait for GitLab API to be ready
until sudo docker exec gitlab gitlab-rails runner "puts User.first.username" &>/dev/null; do
    echo "GitLab booting..."
    sleep 15
done
echo "GitLab is ready!"

echo "=== Step 4: GitLab config (optional helpers) ==="
bash scripts/gitlab/gitlab_config.sh
bash scripts/gitlab/gitlab_users_projects.sh
bash scripts/gitlab/gitlab_runner.sh
echo "=== Step 5: DefectDojo ==="

bash scripts/dojo/dojo_setup.sh

echo "=== Step 6: CI Pipeline setup ==="
bash scripts/pipeline/ci_setup.sh

echo "=== DONE! All services are running ==="
echo "Vault: ${VAULT_URL}"
echo "GitLab: ${GITLAB_URL}"
echo "DefectDojo: http://${HOST_IP}:${DOJO_PORT}/"
