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
sudo docker network create devsecops-net 2>/dev/null || true
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
sudo rm -rf /var/lib/docker/volumes/django-defectdojo_defectdojo_media/_data/threat
bash scripts/dojo/dojo_setup.sh

echo "=== Step 5.5: Grafana ==="
# Grafana-nı ayağa qaldır
sudo -E docker compose --env-file .env up -d grafana

# Grafana-nın hazır olmasını gözlə (isteğe bağlı)
sleep 20
echo "Grafana is ready! Access at http://${HOST_IP}:3000"
# Dojo şəbəkəsini tap və qoş
DOJO_NET=$(sudo docker network ls --format "{{.Name}}" | grep defectdojo | head -n 1)
if [ ! -z "$DOJO_NET" ]; then
    echo "Connecting Grafana to $DOJO_NET..."
    sudo docker network connect "$DOJO_NET" grafana || true
else
    echo "Warning: Dojo network not found. Manual connection might be needed."
fi

echo "=== Step 5.6: Auto-verifying Data Source via API ==="
# Grafana-nın tam hazır olması üçün 5 saniyə gözləyirik
sleep 5

# 1. Data Source-un UID-sini dinamik olaraq tapırıq
DS_UID=$(curl -s -u admin:admin http://localhost:3000/api/datasources/name/DefectDojo_Postgres | jq -r '.uid')

if [ "$DS_UID" != "null" ] && [ ! -z "$DS_UID" ]; then
    echo "Verifying Data Source with UID: $DS_UID"
    # 2. 'Health' check sorğusu göndəririk (Bu, 'Save & Test' düyməsi ilə eyni işi görür)
    CHECK_RESULT=$(curl -s -X GET -u admin:admin "http://localhost:3000/api/datasources/uid/$DS_UID/health")
    echo "Verification Result: $CHECK_RESULT"
    if echo "$CHECK_RESULT" | grep -q "OK"; then
        echo "Data Source is working perfectly!"
    else
        echo "Warning: Data Source connected but health check returned an issue."
    fi
else
    echo "Error: Could not find Data Source UID. Check if ds_dojo.yaml is loaded correctly."
fi

sleep 5
#---------------------------------------------------------------------------------------
echo "=== Step 6: CI Pipeline setup ==="
bash scripts/pipeline/ci_setup.sh

echo "=== DONE! All services are running ==="
echo "Vault: ${VAULT_URL}"
echo "GitLab: ${GITLAB_URL}"
echo "DefectDojo: http://${HOST_IP}:${DOJO_PORT}/"
