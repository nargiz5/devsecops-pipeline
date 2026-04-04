#!/bin/bash
set -euo pipefail

echo "Installing dependencies..."

sudo apt-get update

sudo apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  jq \
  openssl \
  git

echo "Dependencies installed!"
