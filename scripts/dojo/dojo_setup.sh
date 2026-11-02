#!/bin/bash
set -e

# -----------------------------
# 1. Setup Paths and Environment
# -----------------------------
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PROJECT_ROOT/scripts/vault/fetch_secrets.sh"
export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)

# Pull configuration from Vault
DOJO_ADMIN_USER=$(get_vault_secret "dojo_admin_user")
DOJO_ADMIN_PASSWORD=$(get_vault_secret "dojo_admin_password")
IMPORT_PROJECT_NAME=$(get_vault_secret "import_project_name")
DOJO_URL=$(get_vault_secret "dojo_url")

DOJO_DIR="$HOME/django-DefectDojo"

# Generate unique product and engagement names
TIMESTAMP=$(date +%s)
PRODUCT_NAME="$IMPORT_PROJECT_NAME-$TIMESTAMP"
ENGAGEMENT_NAME="CI-CD Scan $TIMESTAMP"


# -----------------------------
# 2. Get / Update DefectDojo
# -----------------------------
echo "Checking DefectDojo Repository..."
if [ -d "$DOJO_DIR" ]; then
    echo "Directory exists. Pulling latest changes..."
    cd "$DOJO_DIR"
    git pull origin master || echo "Git pull failed, using local copy."
else
    echo "Cloning fresh repository..."
    git clone --depth 1 https://github.com/DefectDojo/django-DefectDojo.git "$DOJO_DIR"
    cd "$DOJO_DIR"
fi

# -----------------------------
# 3. Clean Docker Environment (SAFE WAY)
# -----------------------------
echo "Wiping Data for Fresh Environment..."

sudo docker compose down -v --remove-orphans

# Remove only DefectDojo-related volumes
sudo docker volume rm $(docker volume ls -q | grep django-defectdojo) 2>/dev/null || true

# Clean unused Docker resources
sudo docker system prune -f

# Small delay to avoid race conditions
sleep 5

# -----------------------------
# 4. Start DefectDojo
# -----------------------------
echo "Starting DefectDojo..."
sudo docker compose up -d

# -----------------------------
# 5. Wait for API
# -----------------------------
echo "Waiting for DefectDojo API at $DOJO_URL..."

until curl -s "$DOJO_URL/api/v2/system_settings/" > /dev/null; do
    echo "Dojo is booting... (15s sleep)"
    sleep 15
done

# Extra buffer (migrations, workers)
sleep 15

# -----------------------------
# 6. Configure Admin User
# -----------------------------
echo "Configuring Admin User..."

sudo docker compose exec -T uwsgi python3 manage.py shell -c "
from django.contrib.auth.models import User
try:
    user = User.objects.get(username='$DOJO_ADMIN_USER')
    user.set_password('$DOJO_ADMIN_PASSWORD')
    user.save()
except User.DoesNotExist:
    User.objects.create_superuser('$DOJO_ADMIN_USER', 'admin@localhost', '$DOJO_ADMIN_PASSWORD')
"

# -----------------------------
# 7. Get API Key
# -----------------------------
echo "Extracting API Key..."

DEFECTDOJO_API_KEY=$(sudo docker compose exec -T uwsgi python3 manage.py shell -c "
from rest_framework.authtoken.models import Token
from django.contrib.auth.models import User
user = User.objects.get(username='$DOJO_ADMIN_USER')
token, created = Token.objects.get_or_create(user=user)
print(token.key)
" | grep -oE '[a-f0-9]{40}' | head -n 1)

# Save to Vault
push_vault_secret "dojo_api_key" "$DEFECTDOJO_API_KEY"

# -----------------------------
# 8. Create Product
# -----------------------------
echo "Creating Product..."

PRODUCT_RESPONSE=$(curl -s -X POST "$DOJO_URL/api/v2/products/" \
  -H "Authorization: Token $DEFECTDOJO_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"$PRODUCT_NAME\",
    \"description\": \"Automated CI Project\",
    \"prod_type\": 1
  }")

PRODUCT_ID=$(echo "$PRODUCT_RESPONSE" | grep -oP '"id":\s*\K\d+' | head -n 1)
push_vault_secret "dojo_product_name" "$PRODUCT_NAME"


# -----------------------------
# 9. Create Engagement
# -----------------------------
echo "Creating Engagement..."

ENGAGEMENT_RESPONSE=$(curl -s -X POST "$DOJO_URL/api/v2/engagements/" \
  -H "Authorization: Token $DEFECTDOJO_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"target_start\": \"$(date +%Y-%m-%d)\",
    \"target_end\": \"2026-12-31\",
    \"product\": $PRODUCT_ID,
    \"status\": \"In Progress\",
    \"engagement_type\": \"Interactive\",
    \"name\": \"$ENGAGEMENT_NAME\"
  }")

ENGAGEMENT_ID=$(echo "$ENGAGEMENT_RESPONSE" | grep -oP '"id":\s*\K\d+' | head -n 1)

push_vault_secret "dojo_engagement_name" "$ENGAGEMENT_NAME"

# Save IDs to Vault
push_vault_secret "dojo_product_id" "$PRODUCT_ID"
push_vault_secret "dojo_engagement_id" "$ENGAGEMENT_ID"

# -----------------------------
# 10. Final Output
# -----------------------------
echo "✅ DefectDojo is READY!"
echo "Product ID: $PRODUCT_ID"
echo "Engagement ID: $ENGAGEMENT_ID"
echo "API Key stored in Vault."
