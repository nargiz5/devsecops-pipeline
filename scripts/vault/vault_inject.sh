#!/bin/bash
set -e

# Load environment variables
export $(grep -v '^#' ../../.env | xargs)

echo "🔑 Injecting secrets into Vault..."

curl --silent --header "X-Vault-Token: ${VAULT_TOKEN}" \
     --request POST \
     --data "{
       \"data\": {
         \"gitlab_url\": \"http://${HOST_IP}:${GITLAB_PORT}\",
         \"registry_url\": \"http://${HOST_IP}:${REGISTRY_PORT}\",
         \"dojo_url\": \"http://${HOST_IP}:${DOJO_PORT}/\",
         \"root_password\": \"${ROOT_PASSWORD}\",
         \"admin_username\": \"${ADMIN_USERNAME}\",
         \"admin_password\": \"${ADMIN_PASSWORD}\",
         \"admin_email\": \"${ADMIN_EMAIL}\",
         \"user_username\": \"${USER_USERNAME}\",
         \"user_password\": \"${USER_PASSWORD}\",
         \"user_email\": \"${USER_EMAIL}\",
         \"dockerhub_username\": \"${DOCKERHUB_USERNAME}\",
         \"dockerhub_pat\": \"${DOCKERHUB_PAT}\",
         \"import_url\": \"${IMPORT_URL}\",
         \"import_project_name\": \"${IMPORT_PROJECT_NAME}\",
         \"dojo_admin_user\": \"${DOJO_ADMIN_USER}\",
         \"dojo_admin_password\": \"${DOJO_ADMIN_PASSWORD}\"
       }
     }" \
     "${VAULT_URL}/v1/secret/data/devsecops"

echo "✅ All secrets successfully injected into Vault!"
