#!/usr/bin/env bash
# Install k3s server on the OCI VM.
# Run as root (or with sudo).
#
# Prerequisites:
#   - Tailscale is installed and authenticated on this node.
#   - Tailscale IP of THIS node is what we'll bind to.
#
# Usage:
#   sudo TS_IP=$(tailscale ip -4 | head -n1) ./install-server.sh
#
# After the script finishes, the kubeconfig is at /etc/rancher/k3s/k3s.yaml
# and the cluster join token is at /var/lib/rancher/k3s/server/node-token.

set -euo pipefail

TS_IP="${TS_IP:-}"
if [ -z "$TS_IP" ]; then
  TS_IP=$(tailscale ip -4 2>/dev/null | head -n1 || true)
fi

if [ -z "$TS_IP" ]; then
  echo "ERROR: Tailscale is not up on this node. Install and authenticate Tailscale first." >&2
  exit 1
fi

echo "Installing k3s server, advertising Tailscale IP $TS_IP..."

curl -sfL https://get.k3s.io | sh -s - server \
  --node-external-ip "$TS_IP" \
  --flannel-backend=wireguard-native \
  --tls-san "$TS_IP" \
  --tls-san "$(hostname)" \
  --write-kubeconfig-mode 644

echo
echo "k3s server installed."
echo
echo "Cluster join token (agents will need this):"
sudo cat /var/lib/rancher/k3s/server/node-token
echo
echo "Kubeconfig: /etc/rancher/k3s/k3s.yaml"
echo "  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
echo "  kubectl get nodes"
