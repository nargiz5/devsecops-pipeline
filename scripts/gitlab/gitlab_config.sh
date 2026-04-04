#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PROJECT_ROOT/scripts/vault/fetch_secrets.sh"
export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)

echo "🛠️ Step 5: Enabling all import sources..."

# Use SINGLE QUOTES (') here so Bash doesn't get confused by 'app'
sudo docker exec gitlab-new2 gitlab-rails runner "
app = ApplicationSetting.last
app.update!(
  import_sources: [
    'github', 
    'bitbucket', 
    'bitbucket_server', 
    'fogbugz', 
    'gitlab_project', 
    'gitea', 
    'git'
  ]
)"

echo "🎫 Step 6: Generating root personal access token..."

ROOT_TOKEN=$(openssl rand -hex 32)

sudo docker exec gitlab-new2 gitlab-rails runner "
user = User.find_by_username('root')
user.personal_access_tokens.where(name: 'boot-token').destroy_all
token = user.personal_access_tokens.create!(scopes: [:api, :sudo], name: 'boot-token', expires_at: Date.today + 365)
token.set_token('$ROOT_TOKEN')
token.save!
"

push_vault_secret "gitlab_root_token" "$ROOT_TOKEN"
echo "✅ Root token stored in Vault."
