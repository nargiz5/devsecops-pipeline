#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PROJECT_ROOT/scripts/vault/fetch_secrets.sh"
export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)

echo "Pulling Integration Secrets from Vault..."
# Pulling everything we saved earlier

# === Config ===
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PROJECT_ROOT/scripts/vault/fetch_secrets.sh"
export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)

GITLAB_URL=$(get_vault_secret "gitlab_url")
ADMIN_TOKEN=$(get_vault_secret "gitlab_admin_token")
PROJECT_ID=$(get_vault_secret "gitlab_project_id")
DOJO_URL=$(get_vault_secret "dojo_url")
DOJO_KEY=$(get_vault_secret "dojo_api_key")
ENGAGEMENT_ID=$(get_vault_secret "dojo_engagement_id")

PRIVATE_REGISTRY=$(get_vault_secret "registry_url")
REGISTRY_USER=$(get_vault_secret "admin_username")
REGISTRY_PASS=$(get_vault_secret "admin_password")

# --- ADD THIS LINE TO REMOVE http:// or https:// ---
PRIVATE_REGISTRY=$(echo "$PRIVATE_REGISTRY" | sed -e 's|^http://||' -e 's|^https://||')
# --------------------------------------------------

IMAGE_PREFIX="$PRIVATE_REGISTRY/adminuser/django-nv-import/sast-tools"

echo "creating image in container registry"

sudo docker pull python:3.11-slim
sudo docker pull curlimages/curl:latest
# Pull official semgrep image
sudo docker pull registry.gitlab.com/security-products/semgrep:latest

# Tag for your GitLab container registry
sudo docker tag registry.gitlab.com/security-products/semgrep:latest $IMAGE_PREFIX/semgrepp:latest
# Login to GitLab registry (use your GitLab username and personal access token with read/write registry)
echo "$REGISTRY_PASS" | sudo docker login $PRIVATE_REGISTRY -u "$REGISTRY_USER" --password-stdin
# Push the image
sudo docker push $IMAGE_PREFIX/semgrepp:latest



# Encode credentials for DOCKER_AUTH_CONFIG
AUTH_B64=$(echo -n "$REGISTRY_USER:$REGISTRY_PASS" | base64)

# Create the CI content
# Create the CI content
CI_FILE_CONTENT=$(cat <<EOF
stages:
  - test
  - upload

variables:
  SAST_ANALYZER_IMAGE_PREFIX: "$IMAGE_PREFIX"
  DOCKER_AUTH_CONFIG: >-
    {
      "auths": {
        "$PRIVATE_REGISTRY": {
          "auth": "$AUTH_B64"
        }
      }
    }

semgrep-sast:
  stage: test
  image: \$SAST_ANALYZER_IMAGE_PREFIX/semgrepp:latest
  artifacts:
    reports:
      sast: gl-sast-report.json
    paths:
      - gl-sast-report.json
    when: always
  script:
    - /analyzer run

upload_to_defectdojo:
  stage: upload
  image: curlimages/curl:latest
  needs:
    - job: semgrep-sast
      artifacts: true
  script:
    - >
      curl -X POST "$DOJO_URL/api/v2/import-scan/"
      -H "Authorization: Token $DOJO_KEY"
      -F "active=true"
      -F "verified=true"
      -F "scan_type=GitLab SAST Report"
      -F "minimum_severity=High"
      -F "engagement=$ENGAGEMENT_ID"
      -F "file=@gl-sast-report.json"
EOF
)

# Encode CI file and push to GitLab
ENCODED_CI=$(jq -Rs . <<< "$CI_FILE_CONTENT")

curl --silent --request PUT "$GITLAB_URL/api/v4/projects/$PROJECT_ID/repository/files/.gitlab-ci.yml" \
  --header "PRIVATE-TOKEN: $ADMIN_TOKEN" \
  --header "Content-Type: application/json" \
  --data "{
    \"branch\": \"main\",
    \"commit_message\": \"Add automated DevSecOps Pipeline with private registry\",
    \"content\": $ENCODED_CI
  }"

echo "✅ .gitlab-ci.yml pushed! Pipeline should now pull your private registry image securely."
