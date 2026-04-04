#!/bin/bash
set -e

# 1. Setup Paths and Environment
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PROJECT_ROOT/scripts/vault/fetch_secrets.sh"
export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)

# Pull configuration from Vault
DOJO_ADMIN_USER=$(get_vault_secret "dojo_admin_user")
DOJO_ADMIN_PASSWORD=$(get_vault_secret "dojo_admin_password")
IMPORT_PROJECT_NAME=$(get_vault_secret "import_project_name")
DOJO_URL=$(get_vault_secret "dojo_url")

DOJO_DIR="$HOME/django-DefectDojo"

echo "📥 Checking DefectDojo Repository..."
if [ -d "$DOJO_DIR" ]; then
    echo "✅ Directory exists. Pulling latest changes instead of cloning..."
    cd "$DOJO_DIR"
    git pull origin master || echo "⚠️ Warning: Git pull failed, proceeding with local copy."
else
    echo "🚀 Cloning fresh repository..."
    git clone --depth 1 https://github.com/DefectDojo/django-DefectDojo.git "$DOJO_DIR"
    cd "$DOJO_DIR"
fi

echo "🧹 Wiping Data for Fresh Environment..."
# This stops containers AND deletes the persistent volumes (databases/storage)
sudo docker compose down -v --remove-orphans

# Extra safety: Clean up specific Docker volumes if the 'down -v' missed anything
sudo docker volume prune -f


echo "🧹 Cleaning up Docker conflicts..."
sudo docker compose down || true
sudo rm -rf /var/lib/docker/volumes/django-defectdojo_defectdojo_media/_data/threat 2>/dev/null || true

echo "🚀 Starting DefectDojo..."
sudo docker compose up -d

echo "⏳ Waiting for DefectDojo API at $DOJO_URL..."
until curl -s "$DOJO_URL/api/v2/system_settings/" > /dev/null; do
    echo "Dojo is booting... (15s sleep)"
    sleep 15
done
sleep 15 # Buffer for migrations

echo "👤 Configuring Admin User..."
sudo docker compose exec -T uwsgi python3 manage.py shell -c "
from django.contrib.auth.models import User
try:
    user = User.objects.get(username='$DOJO_ADMIN_USER')
    user.set_password('$DOJO_ADMIN_PASSWORD')
    user.save()
except User.DoesNotExist:
    User.objects.create_superuser('$DOJO_ADMIN_USER', 'admin@localhost', '$DOJO_ADMIN_PASSWORD')
"

echo "🔑 Extracting API Key..."
DEFECTDOJO_API_KEY=$(sudo docker compose exec -T uwsgi python3 manage.py shell -c "
from rest_framework.authtoken.models import Token
from django.contrib.auth.models import User
user = User.objects.get(username='$DOJO_ADMIN_USER')
token, created = Token.objects.get_or_create(user=user)
print(token.key)
" | grep -oE '[a-f0-9]{40}' | head -n 1)

# Push API Key to Vault
push_vault_secret "dojo_api_key" "$DEFECTDOJO_API_KEY"

echo "🏗️ Creating Product & Engagement..."
# Create Product
PRODUCT_RESPONSE=$(curl -s -X POST "$DOJO_URL/api/v2/products/" \
  -H "Authorization: Token $DEFECTDOJO_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$IMPORT_PROJECT_NAME-$(date +%s)\", \"description\": \"Automated CI Project\", \"prod_type\": 1}")
PRODUCT_ID=$(echo "$PRODUCT_RESPONSE" | jq -r '.id')

# Create Engagement
ENGAGEMENT_RESPONSE=$(curl -s -X POST "$DOJO_URL/api/v2/engagements/" \
  -H "Authorization: Token $DEFECTDOJO_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"target_start\": \"$(date +%Y-%m-%d)\",
    \"target_end\": \"2026-12-31\",
    \"product\": $PRODUCT_ID,
    \"status\": \"In Progress\",
    \"engagement_type\": \"Interactive\",
    \"title\": \"CI/CD Automated Scan\"
  }")
ENGAGEMENT_ID=$(echo "$ENGAGEMENT_RESPONSE" | jq -r '.id')

# Push IDs to Vault
push_vault_secret "dojo_product_id" "$PRODUCT_ID"
push_vault_secret "dojo_engagement_id" "$ENGAGEMENT_ID"

echo "✅ DefectDojo ready. IDs synced to Vault: Product=$PRODUCT_ID, Engagement=$ENGAGEMENT_ID"
