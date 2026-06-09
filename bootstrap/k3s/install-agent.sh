#!/usr/bin/env bash
# Install k3s agent on a worker node (Rocky or Mac Mini) and join the cluster.
# Run as root (or with sudo).
#
# Prerequisites:
#   - Tailscale is installed and authenticated on this node.
#   - You have the cluster join token from the server.
#
# Usage:
#   sudo K3S_URL=https://<tailscale-ip-of-server>:6443 K3S_TOKEN=<token> ./install-agent.sh

set -euo pipefail

K3S_URL="${K3S_URL:-}"
K3S_TOKEN="${K3S_TOKEN:-}"

if [ -z "$K3S_URL" ] || [ -z "$K3S_TOKEN" ]; then
  echo "ERROR: K3S_URL and K3S_TOKEN must be set." >&2
  echo "  K3S_URL=https://<tailscale-ip-of-server>:6443" >&2
  echo "  K3S_TOKEN=\$(sudo cat /var/lib/rancher/k3s/server/node-token on the server)" >&2
  exit 1
fi

echo "Installing k3s agent, joining $K3S_URL..."

curl -sfL https://get.k3s.io | sh -s - agent \
  --server "$K3S_URL" \
  --token "$K3S_TOKEN" \
  --node-external-ip "$(tailscale ip -4 | head -n1)"

echo
echo "k3s agent installed. Verify from the server:"
echo "  kubectl get nodes"
