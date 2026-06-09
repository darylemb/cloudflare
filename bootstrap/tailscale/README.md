# Tailscale setup for the 3-node cluster

Tailscale provides the overlay network that connects the 3 nodes of the k3s cluster (Rocky + Mac Mini at home, OCI VM in the cloud) into a single mesh so that k3s agents can reach the control plane and pods can communicate across nodes regardless of where the work runs.

## Why Tailscale and not direct VPN

- **No port forwarding** on the home router.
- **No static public IPs** required.
- **Free tier covers us** (1 user, 100 devices, no bandwidth cap).
- **MagicDNS** gives stable hostnames (`rocky.ts.net`, `oci-vm.ts.net`) that survive IP changes.
- **Works on macOS** (the Mac Mini) out of the box.

## Topology

| Node | Tailscale IP | Role | Subnet advertised |
|---|---|---|---|
| `oci-vm` | `100.64.0.3` | k3s server + agent (control plane) | `10.0.0.0/16` (OCI VCN) |
| `rocky` | `100.64.0.1` | k3s agent (home) | `192.168.1.0/24` (home LAN) |
| `macmini` | `100.64.0.2` | k3s agent (home) | — |

## Installation on each node

```bash
# Generic install (works on Linux + macOS)
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Re-authenticate on the same Tailscale account (single user)
```

After login, the node appears in your admin console: <https://login.tailscale.com/admin/machines>.

## Pin the Tailscale IPs

The first 100.x address assigned by Tailscale is **stable** as long as the machine key doesn't change. For our k3s bootstrap, we rely on this stability. If a node ever changes IP, re-run `tailscale up --advertise-routes=...` and the IP stays the same.

## Advertise subnet routes

Only the nodes that have other devices on their local network need to advertise routes.

### Rocky (home gateway for the LAN)

```bash
sudo tailscale up --advertise-routes=192.168.1.0/24 --accept-routes
```

Then in the Tailscale admin console, **approve the route** for the `rocky` node (it will show as "needs approval" until you do).

### OCI VM (gateway for the VCN)

```bash
sudo tailscale up --advertise-routes=10.0.0.0/16 --accept-routes
```

Approve the route in the admin console.

### Mac Mini

```bash
sudo tailscale up
```

No subnet route needed (it's behind the Rocky's LAN).

## Enable MagicDNS + HTTPS

In the admin console → DNS:
- Enable **MagicDNS**.
- Add the nameservers of your choice (e.g. `1.1.1.1`) so that Tailscale also forwards external DNS.
- Enable **HTTPS** under "Serve" if you want to expose HTTP services via `https://<node>.<tailnet>.ts.net` (optional, we use Cloudflare Tunnel instead).

## ACLs

The repo ships a baseline ACL in [`acls.json`](./acls.json). It allows:

- All nodes in the tailnet to talk to each other on all ports.
- `tag:k3s-server` nodes to expose the k3s API (`6443`) to `tag:k3s-agent` nodes.
- `tag:admin` (your laptop, optional) to SSH into all nodes.

## Verify

From any node:

```bash
# Check your own IP
tailscale ip -4
# → 100.64.0.x

# Ping other nodes by name
ping oci-vm
ping rocky
ping macmini

# Check route table
ip route show table 52 | head
```

## What Tailscale does NOT do

- It does **not** expose your home services to the public internet — that's Cloudflare Tunnel's job.
- It does **not** replace Cloudflare DNS or Access.
- It does **not** carry the k3s pod-to-pod traffic if the pods are on the same node (Flannel does that).

## Troubleshooting

| Symptom | Fix |
|---|---|
| Node doesn't appear in admin | Re-run `tailscale up`, check `tailscale status`. |
| Subnet route not working | Approve the route in admin → Machines → node → "Edit route settings". |
| `ping` fails between nodes | `tailscale ping <node>` to see where the connection is stuck (DERP vs direct). |
| High latency | Check if you're going through DERP; if so, enable UDP on the network. |
| Mac Mini wakes from sleep disconnected | Tailscale has Tailscale Sleep mode; for our use, disable sleep on the Mac Mini instead. |
