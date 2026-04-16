#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PROJECT_ROOT/scripts/vault/fetch_secrets.sh"
export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)

echo "Pulling Integration Secrets from Vault..."
GITLAB_URL=$(get_vault_secret "gitlab_url")
ADMIN_TOKEN=$(get_vault_secret "gitlab_admin_token")
PROJECT_ID=$(get_vault_secret "gitlab_project_id")
DOJO_URL=$(get_vault_secret "dojo_url")
DOJO_KEY=$(get_vault_secret "dojo_api_key")
ENGAGEMENT_ID=$(get_vault_secret "dojo_engagement_id")
PRODUCT_NAME=$(get_vault_secret "dojo_product_name")
ENGAGEMENT_NAME=$(get_vault_secret "dojo_engagement_name")

PRIVATE_REGISTRY=$(get_vault_secret "registry_url")
REGISTRY_USER=$(get_vault_secret "admin_username")
REGISTRY_PASS=$(get_vault_secret "admin_password")

# Telegram Secrets
TELEGRAM_TOKEN=$(get_vault_secret "telegram_token")
TELEGRAM_CHAT_ID=$(get_vault_secret "telegram_chat_id")

# Clean URL
PRIVATE_REGISTRY=$(echo "$PRIVATE_REGISTRY" | sed -e 's|^http://||' -e 's|^https://||')
IMAGE_PREFIX="$PRIVATE_REGISTRY/adminuser/django-nv-import/sast-tools"

# Pull base images
sudo docker pull python:3.11-slim
sudo docker pull curlimages/curl:latest

# Build Semgrep image
export DOCKER_BUILDKIT=0
TMP_DOCKERFILE=$(mktemp)
cat <<EOF > $TMP_DOCKERFILE
FROM registry.gitlab.com/security-products/semgrep:latest
EOF
sudo docker build -f $TMP_DOCKERFILE -t "$IMAGE_PREFIX/semgrepp:latest" .
rm -f $TMP_DOCKERFILE

# Login & Push
echo "$REGISTRY_PASS" | sudo docker login "$PRIVATE_REGISTRY" -u "$REGISTRY_USER" --password-stdin
sudo docker push "$IMAGE_PREFIX/semgrepp:latest"

AUTH_B64=$(echo -n "$REGISTRY_USER:$REGISTRY_PASS" | base64)

# -----------------------------
# Generate .gitlab-ci.yml
# -----------------------------
CI_OUTPUT="$PROJECT_ROOT/.gitlab-ci.yml"

cat <<EOF > $CI_OUTPUT
stages:
  - test
  - upload
  - gate
variables:
  SAST_ANALYZER_IMAGE_PREFIX: "$IMAGE_PREFIX"
  TELEGRAM_TOKEN: "$TELEGRAM_TOKEN"
  TELEGRAM_CHAT_ID: "$TELEGRAM_CHAT_ID"

  DOCKER_AUTH_CONFIG: >-
    {
      "auths": {
        "$PRIVATE_REGISTRY": {
          "auth": "$AUTH_B64"
        }
      }
    }

# ---------------- TEST 1 ----------------
semgrep-sast:
  stage: test
  image: \$SAST_ANALYZER_IMAGE_PREFIX/semgrepp:latest
  artifacts:
    reports:
      sast: gl-sast-report-1.json
    paths:
      - gl-sast-report-1.json
    when: always
  script:
    - /analyzer run
    - mv gl-sast-report.json gl-sast-report-1.json
    - ls -la

upload-test:
  stage: upload
  image: curlimages/curl:latest
  needs:
    - job: semgrep-sast
      artifacts: true
  script:
    - >
      curl -X POST "$DOJO_URL/api/v2/reimport-scan/"
      -H "Authorization: Token $DOJO_KEY"
      -F "active=true"
      -F "verified=true"
      -F "scan_type=GitLab SAST Report"
      -F "minimum_severity=High"
      -F "product_name=$PRODUCT_NAME"
      -F "engagement_name=$ENGAGEMENT_NAME"
      -F "test_title=Semgrep Scan - Test 1"
      -F "auto_create_context=true"
      -F "file=@gl-sast-report-1.json"

security-gate:
  stage: gate
  image: alpine:latest
  needs: ["upload-test"]
  script:
    - apk add --no-cache curl jq
    - |
      echo "🔍 Verifying security status..."

      # 1. Query DefectDojo
      RESPONSE=$(curl -s -H "Authorization: Token $DOJO_KEY" \
        "$DOJO_URL/api/v2/findings/?active=true&verified=true&test__title=Semgrep%20Scan%20-%20Test%201")

      # 2. Extract Count
      COUNT=$(echo "$RESPONSE" | jq '.count // 0')

      if [ "$COUNT" -gt 0 ]; then
        # Fetch titles, format as bullet points, and escape HTML special characters
        VULN_LIST=$(echo "$RESPONSE" | jq -r '.results[0:5] | .[] | "• " + .title' | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

        # Build the message block - No special commands, just a standard variable
        MSG="🚨 <b>SECURITY GATE ALERT</b>

        <b>Project:</b> <code>$PRODUCT_NAME</code>
        <b>Findings:</b> $COUNT High vulnerabilities

        <b>Top Vulnerabilities:</b>
        $VULN_LIST"

      else
        MSG="✅ <b>SECURITY GATE PASSED</b>

        <b>Project:</b> $PRODUCT_NAME
        No active findings detected."
      fi

      # 3. Send to Telegram
      # --data-urlencode is vital here to handle the newlines in the MSG variable
      curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
        --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
        --data-urlencode "parse_mode=HTML" \
        --data-urlencode "text=$MSG"


EOF


# Push to GitLab
ENCODED_CI=$(jq -Rs . < "$CI_OUTPUT")

curl --silent --request PUT "$GITLAB_URL/api/v4/projects/$PROJECT_ID/repository/files/.gitlab-ci.yml" \
  --header "PRIVATE-TOKEN: $ADMIN_TOKEN" \
  --header "Content-Type: application/json" \
  --data "{
    \"branch\": \"main\",
    \"commit_message\": \"Add automated DevSecOps Pipeline with two independent tests\",
    \"content\": $ENCODED_CI
  }"

echo "✅ .gitlab-ci.yml pushed! Pipeline now has two separate tests."
