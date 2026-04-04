#!/bin/bash
set -euo pipefail

echo "Starting full cleanup..."

# -----------------------------
# Stop & Remove Containers
# -----------------------------
echo "Removing containers..."

containers=(
  gitlab
  gitlab-new2
  gitlab-runner
  gitlab-runner-new2
  vault
  uwsgi
  nginx
  celery
  mysql
  redis
)

for c in "${containers[@]}"; do
  sudo docker rm -f "$c" 2>/dev/null || true
done

# -----------------------------
# Stop Compose Stacks
# -----------------------------
echo "Stopping docker-compose stacks..."

cd ~/docker-compose 2>/dev/null && sudo docker compose down -v --remove-orphans || true
cd ~/django-DefectDojo 2>/dev/null && sudo docker compose down -v --remove-orphans || true
cd ~/vault-docker 2>/dev/null && sudo docker compose down -v --remove-orphans || true

cd ~ || true

# -----------------------------
# Remove Volumes
# -----------------------------
echo "Removing unused volumes..."
sudo docker volume prune -f || true

# -----------------------------
# Remove Networks
# -----------------------------
echo "Cleaning networks..."
sudo docker network prune -f || true

# -----------------------------
# Remove Directories
# -----------------------------
echo "Removing project directories..."

sudo rm -rf /srv/gitlab-new2
sudo rm -rf /srv/gitlab-runner-new2

rm -rf ~/docker-compose
rm -rf ~/django-DefectDojo
rm -rf ~/vault-docker

# -----------------------------
# Remove Dangling Images
# -----------------------------
echo "Cleaning unused images..."
#sudo docker image prune -af || true

# -----------------------------
# Final Message
# -----------------------------
echo "Cleanup completed!"
