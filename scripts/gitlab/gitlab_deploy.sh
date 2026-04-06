#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# 1. Load basic Vault connection info from .env
export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
source "$PROJECT_ROOT/scripts/vault/fetch_secrets.sh"

echo "Pulling GitLab Config from HashiCorp Vault..."

# 2. Pull the URLs and Credentials
GITLAB_URL=$(get_vault_secret "gitlab_url")
REGISTRY_URL=$(get_vault_secret "registry_url")
ROOT_PASSWORD=$(get_vault_secret "root_password")
DOCKERHUB_USERNAME=$(get_vault_secret "dockerhub_username")
DOCKERHUB_PAT=$(get_vault_secret "dockerhub_pat")

# -----------------------------------------------
echo "Creating GitLab Docker Compose..."
cat <<EOF > docker-compose.yml
version: '3.6'
services:
  gitlab:
    image: gitlab/gitlab-ce:latest
    container_name: gitlab-new2
    restart: always
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url '$GITLAB_URL'
        gitlab_rails['initial_root_password'] = '$ROOT_PASSWORD'

        # Registry
        registry_external_url '$REGISTRY_URL'
        registry['enable'] = true
        registry_nginx['enable'] = true
        registry_nginx['listen_port'] = 5005

        gitlab_rails['registry_enabled'] = true
        gitlab_rails['registry_host'] = "localhost"
        gitlab_rails['registry_port'] = 5005
        gitlab_rails['registry_api_url'] = "http://localhost:5005"

        # Paketlər və Nginx
        gitlab_rails['packages_enabled'] = true
        nginx['listen_port'] = 80
        nginx['listen_addresses'] = ['0.0.0.0']
        gitlab_rails['dependency_proxy_enabled'] = true

    ports:
      - "9500:80"
      - "5002:5005"

    volumes:
      - /srv/gitlab-new2/config:/etc/gitlab
      - /srv/gitlab-new2/logs:/var/log/gitlab
      - /srv/gitlab-new2/data:/var/opt/gitlab

  gitlab-runner:
    image: gitlab/gitlab-runner:latest
    container_name: gitlab-runner-new2
    restart: always
    volumes:
      - /srv/gitlab-runner-new2/config:/etc/gitlab-runner
      - /var/run/docker.sock:/var/run/docker.sock
EOF

sudo docker compose up -d

echo "Waiting for GitLab API (this takes time)..."
until sudo docker exec gitlab-new2 gitlab-rails runner "puts User.first.username" &>/dev/null; do
    echo "GitLab booting... (15s sleep)"
    sleep 15
done
echo "GitLab Container is up!"
                                    
