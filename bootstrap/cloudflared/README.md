# cloudflared deployment

This folder contains the k8s manifests for the `cloudflared` DaemonSet that
keeps the Cloudflare Tunnel alive in the cluster.

## Files

- `namespace.yaml` — the `cloudflare` namespace.
- `secret.yaml` — the Tunnel token (template, fill in manually).
- `daemonset.yaml` — RBAC + ConfigMap + DaemonSet + metrics Service.
- `ollama-external-svc.yaml` — example of a Service pointing at Ollama running
  on the Mac Mini host.

## Apply

```bash
# 1. Create the namespace
kubectl apply -f namespace.yaml

# 2. Fill in the secret from the Terraform output
terraform -chdir=../.. output -raw tunnel_token
# paste the result into secret.yaml, then:
kubectl apply -f secret.yaml

# 3. Edit daemonset.yaml and replace REPLACE_WITH_TUNNEL_ID_OR_NAME in the
#    ConfigMap with the value of `terraform output -raw tunnel_id`.
#    Then apply:
kubectl apply -f daemonset.yaml

# 4. (optional) For the LLM service
kubectl create namespace ai
kubectl apply -f ollama-external-svc.yaml
```

## How traffic flows

```
user → Cloudflare Edge → Tunnel (any pod running cloudflared)
     → kube-dns resolves service_url
     → kube-proxy routes to the right node
     → pod (or external Service, like ollama)
```

The DaemonSet runs on **every node** so the Tunnel stays alive even if a node
goes down (Cloudflare load-balances across the active connections).

## Verifying

```bash
# Tunnel is up
kubectl -n cloudflare logs -l app=cloudflared --tail=50

# Tunnel status
kubectl -n cloudflare exec -it $(kubectl -n cloudflare get pod -l app=cloudflared -o name | head -1) -- cloudflared tunnel info

# One of the services
curl -I https://grafana.darylm.xyz
```
