#!/bin/bash
set -e

# 1. Setup
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)

# 2. Execution Flow
echo "🔧 Step 0: OS Prep"
bash scripts/setup/install_dependencies.sh
bash scripts/setup/install_docker.sh

echo "🧹 Step 1: Cleanup"
bash scripts/setup/cleanup_project.sh

echo "🔐 Step 2: Vault"
bash scripts/vault/vault_init.sh
bash scripts/vault/vault_inject.sh

echo "📦 Step 3: GitLab Deploy"
bash scripts/gitlab/gitlab_deploy.sh

echo "🛠️ Step 4: GitLab Config"
bash scripts/gitlab/gitlab_config.sh

echo "👤 Step 5: Users & Projects"
bash scripts/gitlab/gitlab_users_projects.sh

echo "🏃 Step 6: Runner Registration"
bash scripts/gitlab/gitlab_runner.sh

echo "🛡️ Step 7: DefectDojo Setup"
bash scripts/dojo/dojo_setup.sh

echo "🛰️ Step 8: Pipeline Injection"
bash scripts/pipeline/ci_setup.sh

echo "✅ DONE! Services at: http://${HOST_IP}"
