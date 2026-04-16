#!/bin/bash
set -euo pipefail

echo "Installing dependencies..."

sudo apt-get update --fix-missing || true

sudo apt-get install -y --fix-missing \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  jq \
  openssl \
  git




echo "Dependencies installed!"
