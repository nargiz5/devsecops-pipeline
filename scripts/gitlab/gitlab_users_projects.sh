#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PROJECT_ROOT/scripts/vault/fetch_secrets.sh"
export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)

ROOT_TOKEN=$(get_vault_secret "gitlab_root_token")
GITLAB_URL=$(get_vault_secret "gitlab_url")
REGISTRY_URL=$(get_vault_secret "registry_url")

echo "👤 Step 7: Creating Admin user..."
# Fetch admin details from Vault
ADMIN_EMAIL=$(get_vault_secret "admin_email")
ADMIN_PASSWORD=$(get_vault_secret "admin_password")
ADMIN_USERNAME=$(get_vault_secret "admin_username")

until curl_response=$(curl --silent --request POST "$GITLAB_URL/api/v4/users" \
    --header "PRIVATE-TOKEN: $ROOT_TOKEN" \
    --data "email=$ADMIN_EMAIL&password=$ADMIN_PASSWORD&username=$ADMIN_USERNAME&name=SystemAdmin&admin=true&skip_confirmation=true") \
    && ADMIN_ID=$(echo "$curl_response" | jq -r '.id') \
    && [ "$ADMIN_ID" != "null" ]; do
    echo "Waiting for GitLab API to be ready for Admin creation..."
    sleep 10
done

echo "🎫 Step 8: Generating Admin PAT..."
ADMIN_TOKEN=$(openssl rand -hex 32)
sudo docker exec gitlab-new2 gitlab-rails runner "
user = User.find_by_username('$ADMIN_USERNAME')
token = user.personal_access_tokens.create!(scopes: [:api, :read_api, :read_repository, :write_repository, :sudo], name: 'admin-token', expires_at: Date.today + 365)
token.set_token('$ADMIN_TOKEN')
token.save!
"
push_vault_secret "gitlab_admin_token" "$ADMIN_TOKEN"


echo "⏳ Waiting 40 seconds for GitLab to sync permissions..."
sleep 40


echo "📦 Step 9: Creating remote import project..."

IMPORT_URL=$(get_vault_secret "import_url")
IMPORT_PROJECT_NAME=$(get_vault_secret "import_project_name")

RESPONSE=$(curl --silent --request POST "$GITLAB_URL/api/v4/projects" \
    --header "PRIVATE-TOKEN: $ADMIN_TOKEN" \
    --header "Content-Type: application/json" \
    --data "{
      \"name\": \"$IMPORT_PROJECT_NAME\",
      \"visibility\": \"private\",
      \"import_url\": \"$IMPORT_URL\"
    }")

IMPORT_PROJECT_ID=$(echo "$RESPONSE" | jq -r '.id')

# Check if ID is valid. If not, the project probably failed to create.
if [ "$IMPORT_PROJECT_ID" == "null" ] || [ -z "$IMPORT_PROJECT_ID" ]; then
    echo "❌ Error: Project creation failed! Response: $RESPONSE"
    exit 1
fi

push_vault_secret "gitlab_project_id" "$IMPORT_PROJECT_ID"
echo "✅ Project created with ID: $IMPORT_PROJECT_ID"

# Wait a few seconds for the database to index the new project
echo "⏳ Waiting for project indexing..."
sleep 5

push_vault_secret "gitlab_project_id" "$IMPORT_PROJECT_ID"

echo "👤 Step 10: Creating Normal User and adding to project..."
USER_EMAIL=$(get_vault_secret "user_email")
USER_PASSWORD=$(get_vault_secret "user_password")
USER_USERNAME=$(get_vault_secret "user_username")

USER_ID=$(curl --silent --request POST "$GITLAB_URL/api/v4/users" \
    --header "PRIVATE-TOKEN: $ADMIN_TOKEN" \
    --data "email=$USER_EMAIL&password=$USER_PASSWORD&username=$USER_USERNAME&name=StandardUser&skip_confirmation=true" \
    | jq -r '.id')

curl --silent --request POST "$GITLAB_URL/api/v4/projects/$IMPORT_PROJECT_ID/members" \
    --header "PRIVATE-TOKEN: $ADMIN_TOKEN" \
    --data "user_id=$USER_ID&access_level=20"

echo "✅ All users and projects successfully configured."
