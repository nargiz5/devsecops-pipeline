#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
source "$PROJECT_ROOT/scripts/vault/fetch_secrets.sh"

echo "Registering GitLab Runner..."

GITLAB_URL=$(get_vault_secret "gitlab_url")
REGISTRY_URL=$(get_vault_secret "registry_url")

RUNNER_TOKEN=$(sudo docker exec gitlab gitlab-rails runner "puts Gitlab::CurrentSettings.current_application_settings.runners_registration_token")

sudo docker exec gitlab-runner gitlab-runner register \
  --non-interactive \
  --url "$GITLAB_URL" \
  --registration-token "$RUNNER_TOKEN" \
  --executor docker \
  --docker-image "python:3.11-slim" \
  --description "DevSecOps-Auto-Runner" \
  --docker-privileged

echo "Runner registered and active."
