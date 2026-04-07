#!/bin/bash
set -e

echo "🚀 Bootstrapping GitLab..."

./gitlab_deploy.sh
./gitlab_config.sh
./gitlab_users_projects.sh
./gitlab_runner.sh

echo "✅ GitLab ready!"
