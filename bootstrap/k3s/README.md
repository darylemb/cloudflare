# k3s bootstrap

## Topology

- **Server (control plane)**: OCI VM — runs 24/7 in the free tier. Has the API + etcd/SQLite.
- **Agents (workers)**: Rocky + Mac Mini at home. They reconnect to the server automatically when they boot.

The server binds to its Tailscale IP (`100.64.0.3`) so all control-plane traffic goes over the Tailscale mesh — the OCI VM does not need to expose port 6443 to the public internet.

## Prerequisites

1. Tailscale installed and authenticated on all 3 nodes (see [`../tailscale/README.md`](../tailscale/README.md)).
2. Tailscale IP of the OCI VM known (`tailscale ip -4` on the OCI VM).

## Step 1 — Install k3s server on OCI

```bash
# On the OCI VM
chmod +x install-server.sh
sudo TS_IP=$(tailscale ip -4 | head -n1) ./install-server.sh
```

The script prints the cluster join token. **Save it** for step 2.

## Step 2 — Install k3s agents on Rocky and Mac Mini

```bash
# On Rocky and on Mac Mini (replace with the real Tailscale IP and token)
chmod +x install-agent.sh
sudo K3S_URL=https://100.64.0.3:6443 K3S_TOKEN=<paste-token-here> ./install-agent.sh
```

## Step 3 — Verify

From the OCI VM:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes -o wide
```

You should see 3 nodes:

```
NAME       STATUS   ROLES                  AGE   VERSION
oci-vm     Ready    control-plane,master   1m    v1.31.x
rocky      Ready    <none>                 30s   v1.31.x
macmini    Ready    <none>                 25s   v1.31.x
```

## Step 4 — Label the nodes

We want to control which workloads run on which machine.

```bash
# General role labels
kubectl label node oci-vm    node-role/dmxyz=cloud
kubectl label node rocky     node-role/dmxyz=home
kubectl label node macmini   node-role/dmxyz=home

# Workload-specific labels (used by nodeSelector / tolerations)
kubectl label node oci-vm    workload/database=true
kubectl label node oci-vm    workload/monitoring=true
kubectl label node rocky     workload/coolify=true
kubectl label node rocky     workload/apps=true
kubectl label node macmini   workload/llm=true
kubectl label node macmini   workload/ml=true
```

## Step 5 — Optional: taint home nodes

If you want workloads to prefer OCI and only spill to home nodes when explicitly allowed:

```bash
kubectl taint nodes rocky     home-only=true:NoSchedule
kubectl taint nodes macmini   home-only=true:NoSchedule
```

Then pods that should run at home need a toleration:

```yaml
tolerations:
- key: home-only
  operator: Equal
  value: "true"
  effect: NoSchedule
```

## Step 6 — Install cloudflared

See [`../cloudflared/README.md`](../cloudflared/README.md) to deploy the Tunnel DaemonSet and point the `services.tfvars` at the k8s Services.

## What survives a power outage at home

| Failure | Behavior |
|---|---|
| Rocky goes down | Workloads on Rocky reschedule to OCI (or wait on taint). |
| Mac Mini goes down | Ollama and MLX workloads reschedule to OCI; LLM stays down (no GPU there). |
| OCI goes down | Control plane is gone — kubectl stops working until OCI comes back. |
| Tailscale goes down | Nodes can't reach each other; everything stalls. (Tailscale has had < 30 min of global downtime per year historically.) |
| House internet goes down (Tailscale relay works) | Tailscale falls back to DERP; cluster still works, just slower. |

## Local kubectl from your laptop

Install Tailscale on your laptop too, then:

```bash
scp oci-vm:/etc/rancher/k3s/k3s.yaml ~/.kube/dmxyz-config
# Edit the server URL to https://100.64.0.3:6443 (the Tailscale IP, not the public IP)
export KUBECONFIG=~/.kube/dmxyz-config
kubectl get nodes
```
