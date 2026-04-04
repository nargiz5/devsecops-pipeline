#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PROJECT_ROOT/scripts/vault/fetch_secrets.sh"
export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)

echo "🛰️ Pulling Integration Secrets from Vault..."
# Pulling everything we saved earlier
GITLAB_URL=$(get_vault_secret "gitlab_url")
ADMIN_TOKEN=$(get_vault_secret "gitlab_admin_token")
PROJECT_ID=$(get_vault_secret "gitlab_project_id")
DOJO_URL=$(get_vault_secret "dojo_url")
DOJO_KEY=$(get_vault_secret "dojo_api_key")
ENGAGEMENT_ID=$(get_vault_secret "dojo_engagement_id")

# 1. Define the CI Content (Using the actual Dojo variables)
CI_FILE_CONTENT=$(cat <<EOF
stages:
  - test
  - upload

sast_scan:
  stage: test
  image: python:3.11-slim
  script:
    - pip install bandit
    - bandit -r . -f json -o gl-sast-report.json || true
  artifacts:
    paths:
      - gl-sast-report.json

upload_to_defectdojo:
  stage: upload
  image: curlimages/curl:latest
  script:
    - |
      curl -X POST "$DOJO_URL/api/v2/import-scan/" \\
      -H "Authorization: Token $DOJO_KEY" \\
      -F "scan_type=Bandit Scan" \\
      -F "file=@gl-sast-report.json" \\
      -F "engagement=$ENGAGEMENT_ID" \\
      -F "minimum_severity=High" \
      -F "active=true" \\
      -F "verified=true" \\
      -F "close_old_findings=true"
EOF
)

echo "⏳ Waiting for repository to settle..."
sleep 15

# 2. Upload the file via GitLab API (POST if new, PUT if updating)
echo "🚀 Injecting .gitlab-ci.yml into Project #$PROJECT_ID..."
ENCODED_CI=$(jq -Rs . <<< "$CI_FILE_CONTENT")

curl --silent --request PUT "$GITLAB_URL/api/v4/projects/$PROJECT_ID/repository/files/.gitlab-ci.yml" \
  --header "PRIVATE-TOKEN: $ADMIN_TOKEN" \
  --header "Content-Type: application/json" \
  --data "{
    \"branch\": \"main\",
    \"commit_message\": \"Add automated DevSecOps Pipeline\",
    \"content\": $ENCODED_CI
  }"

echo "🏁 Triggering initial security pipeline..."

echo "✅ SUCCESS! The pipeline is now running."
echo "Check it here: $GITLAB_URL/dashboard/projects"
