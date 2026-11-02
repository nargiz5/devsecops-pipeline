#!/bin/bash
# simplified_insecure_reg.sh
export $(grep -v '^#' ../../.env | xargs)

INSECURE_REGISTRY="${HOST_IP}:${REGISTRY_PORT}"

DOCKER_DAEMON_CONFIG="/etc/docker/daemon.json"

echo "Configuring Docker..."

# Create the directory if it doesn't exist
sudo mkdir -p /etc/docker

# Overwrite with a clean, simple JSON structure
sudo tee $DOCKER_DAEMON_CONFIG <<EOF
{
  "insecure-registries": ["$INSECURE_REGISTRY"]
}
EOF

echo "Restarting Docker..."
sudo systemctl daemon-reload
sudo systemctl restart docker

# Final check
sudo docker info | grep "Insecure Registries" -A 1
