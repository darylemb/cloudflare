#!/usr/bin/env bash
# One-shot bootstrap for the dmxyz cluster.
# Run from your Mac (the one running this script). It will reach the 3 nodes
# over Tailscale and set up k3s + cloudflared + Ollama service.
#
# Requirements:
#   - Tailscale installed and authenticated on this Mac (you can ping the nodes).
#   - You have the OCI node-token from step 1.
#   - You have your Cloudflare API token, account ID, zone ID handy.
#
# Usage:
#   K3S_TOKEN=<paste-from-server> ./bootstrap-cluster.sh

set -euo pipefail

OCI_IP="${OCI_IP:-100.64.0.3}"
ROCKY_IP="${ROCKY_IP:-100.64.0.1}"
MACMINI_IP="${MACMINI_IP:-100.64.0.2}"
K3S_TOKEN="${K3S_TOKEN:-}"
CF_API_TOKEN="${CF_API_TOKEN:-}"
CF_ACCOUNT_ID="${CF_ACCOUNT_ID:-}"
CF_ZONE_ID="${CF_ZONE_ID:-}"

if [ -z "$K3S_TOKEN" ]; then
  echo "ERROR: K3S_TOKEN is required. Get it from the OCI VM with:" >&2
  echo "  sudo cat /var/lib/rancher/k3s/server/node-token" >&2
  exit 1
fi

step() { printf "\n\033[1;36m▶ %s\033[0m\n" "$1"; }
ok()   { printf "\033[1;32m✓\033[0m %s\n" "$1"; }
warn() { printf "\033[1;33m!\033[0m %s\n" "$1"; }

step "0. Verify Tailscale mesh"
tailscale status | grep -E "(oci|rocky|macmini)" || { warn "Tailscale mesh not detected. Continuing anyway."; }

step "1. SSH to OCI VM, install k3s server (idempotent)"
ssh -o StrictHostKeyChecking=accept-new opc@"$OCI_IP" "command -v k3s >/dev/null && echo 'k3s already installed' || (curl -sfL https://get.k3s.io | sh -s - server --node-external-ip $OCI_IP --flannel-backend=wireguard-native --tls-san $OCI_IP --tls-san \$(hostname) --write-kubeconfig-mode 644)"
ok "k3s server up on $OCI_IP"

step "2. SSH to Rocky, install k3s agent (idempotent)"
ssh -o StrictHostKeyChecking=accept-new user@"$ROCKY_IP" "command -v k3s >/dev/null && echo 'k3s agent already installed' || curl -sfL https://get.k3s.io | K3S_URL=https://$OCI_IP:6443 K3S_TOKEN=$K3S_TOKEN sh -s - agent --node-external-ip $ROCKY_IP"
ok "k3s agent up on $ROCKY_IP"

step "3. SSH to Mac Mini, install k3s agent (idempotent)"
ssh -o StrictHostKeyChecking=accept-new user@"$MACMINI_IP" "command -v k3s >/dev/null && echo 'k3s agent already installed' || curl -sfL https://get.k3s.io | K3S_URL=https://$OCI_IP:6443 K3S_TOKEN=$K3S_TOKEN sh -s - agent --node-external-ip $MACMINI_IP"
ok "k3s agent up on $MACMINI_IP"

step "4. Label and taint nodes"
ssh opc@"$OCI_IP" "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && \
  kubectl label node \$(hostname) node-role/dmxyz=cloud workload/database=true workload/monitoring=true --overwrite && \
  kubectl label node rocky node-role/dmxyz=home workload/coolify=true --overwrite || true && \
  kubectl label node macmini node-role/dmxyz=home workload/llm=true workload/ml=true --overwrite || true && \
  kubectl taint nodes rocky home-only=true:NoSchedule --overwrite || true && \
  kubectl taint nodes macmini home-only=true:NoSchedule --overwrite || true"
ok "Nodes labelled and tainted"

step "5. Install Ollama on Mac Mini (skip if already installed)"
ssh user@"$MACMINI_IP" "command -v ollama >/dev/null || (brew install ollama && ollama serve >/dev/null 2>&1 &)"
ssh user@"$MACMINI_IP" "ollama pull qwen3.5:4b || true"
ok "Ollama ready on $MACMINI_IP:11434"

step "6. Apply Ollama Service in k3s"
ssh opc@"$OCI_IP" "kubectl create namespace ai --dry-run=client -o yaml | kubectl apply -f -"
scp "$(dirname "$0")/cloudflared/ollama-external-svc.yaml" opc@"$OCI_IP":~/
ssh opc@"$OCI_IP" "kubectl apply -f ollama-external-svc.yaml -n ai"
ok "Ollama Service exposed in k3s"

step "7. Verify cluster"
ssh opc@"$OCI_IP" "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get nodes -o wide && echo --- && kubectl get svc -n ai ollama"
ok "Cluster is up"

if [ -n "$CF_API_TOKEN" ] && [ -n "$CF_ACCOUNT_ID" ] && [ -n "$CF_ZONE_ID" ]; then
  step "8. Apply Cloudflare Tunnel via Terraform (this repo)"
  cd "$(dirname "$0")/.."
  if [ ! -f services.tfvars ] || [ ! -f backend.tfvars ]; then
    cp services.tfvars.example services.tfvars
    cp backend.tfvars.example backend.tfvars
    warn "Edit services.tfvars and backend.tfvars before continuing."
    warn "Re-run this script with the env vars set after editing."
    exit 0
  fi
  export TF_VAR_cloudflare_api_token="$CF_API_TOKEN"
  export TF_VAR_cloudflare_account_id="$CF_ACCOUNT_ID"
  export TF_VAR_cloudflare_zone_id="$CF_ZONE_ID"
  terraform init -backend-config=backend.tfvars
  terraform apply -auto-approve -var-file=services.tfvars -var-file=terraform.tfvars
  TUNNEL_TOKEN=$(terraform output -raw tunnel_token)
  ok "Tunnel created. Token captured."

  step "9. Apply cloudflared DaemonSet in k3s"
  ssh opc@"$OCI_IP" "kubectl create namespace cloudflare --dry-run=client -o yaml | kubectl apply -f -"
  TMPF=$(mktemp)
  sed "s/PASTE_TUNNEL_TOKEN_HERE/$TUNNEL_TOKEN/" "$(dirname "$0")/cloudflared/secret.yaml" > "$TMPF"
  scp "$TMPF" opc@"$OCI_IP":~/secret.yaml
  ssh opc@"$OCI_IP" "kubectl apply -f secret.yaml -n cloudflare && kubectl apply -f - <<'YAML'
$(cat "$(dirname "$0")/cloudflared/daemonset.yaml")
YAML"
  rm "$TMPF"
  ok "cloudflared DaemonSet deployed"
else
  warn "Skipping Cloudflare step (CF_API_TOKEN, CF_ACCOUNT_ID, CF_ZONE_ID not set)."
  warn "Set them and run 'terraform apply' manually, then apply bootstrap/cloudflared/secret.yaml + daemonset.yaml."
fi

step "All done"
echo "Cluster:    kubectl --kubeconfig=<path-to-k3s.yaml> get nodes"
echo "Tunnel:     curl -I https://grafana.darylm.xyz"
echo "LLM:        curl https://llm.darylm.xyz/api/tags"
