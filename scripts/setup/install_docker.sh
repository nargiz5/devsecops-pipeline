#!/bin/bash
set -euo pipefail

echo "Installing Docker..."

if command -v docker &> /dev/null; then
    echo "Docker already installed"
else
    echo "Setting up Docker repository..."

    sudo mkdir -p /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) \
      signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update

    sudo apt-get install -y \
      docker-ce \
      docker-ce-cli \
      containerd.io \
      docker-compose-plugin
fi

# -----------------------------
# Ensure Docker is running
# -----------------------------
echo "Starting Docker..."
sudo systemctl enable docker
sudo systemctl start docker

# -----------------------------
# Add user to docker group
# -----------------------------
sudo usermod -aG docker $USER

echo "Run 'newgrp docker' or relogin to use docker without sudo"

# -----------------------------
# Test
# -----------------------------
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -f "$PROJECT_ROOT/.env" ]; then
    export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
    
    # --- ADD THIS LOGIC HERE ---
    echo "Logging into Docker Hub to avoid rate limits..."
    echo "$DOCKERHUB_PAT" | sudo docker login -u "$DOCKERHUB_USERNAME" --password-stdin
else
    echo "Warning: .env file not found at $PROJECT_ROOT/.env"
fi
echo "Testing Docker..."
sudo docker run hello-world

echo "Docker ready!"
