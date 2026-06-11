# cloudflare

Manages the Cloudflare layer (DNS + Access) for the **dmxyz** homelab + cloud
cluster. Terraform against the Cloudflare API, deployed via GitHub Actions,
state stored in the OCI bucket.

The cluster is 1+ nodes joined into one k3s cluster over a Tailscale mesh:

| Node | Where | Role | Status |
|---|---|---|---|
| OCI VM (A1.Flex, Always Free) | Cloud (Ashburn) | k3s server (control plane) + worker | 24/7 |
| Rocky Linux 10.2 | Home | k3s agent | standby (rejoin when needed) |
| Mac Mini (Apple Silicon) | Home | k3s agent + Ollama/MLX | planned |

Public traffic comes in through the **OCI Load Balancer** (`k3s-public-lb`),
which does TCP passthrough to the OCI VM on ports 80/443. Cloudflare proxies
the public-facing hostnames (`*.darylm.xyz`) and forwards to the LB's public
IP. The LB only accepts traffic from Cloudflare IP ranges (security list
default-deny). Traefik in the cluster terminates TLS for HTTP routes.

A Cloudflare Tunnel resource is also defined in Terraform (kept around for
future use — TCP services, hiding the origin IP) but the `cloudflared`
DaemonSet is not currently deployed in the cluster. **The active origin for
all HTTP services today is the OCI LB at `129.158.253.31`.**

---

## Layout of this repo

```
cloudflare/
├── .github/workflows/terraform.yml   # Plan on PR, apply on push to main
├── bootstrap/                        # Out-of-band setup for the cluster itself
│   ├── tailscale/                    #   Tailscale mesh (100.64.0.0/10)
│   ├── k3s/                          #   k3s server + agent install scripts
│   └── cloudflared/                  #   DaemonSet manifests for the Tunnel (unused)
├── versions.tf                       # cloudflare/cloudflare >= 5.0.0
├── provider.tf
├── variables.tf
├── locals.tf                         # ingress rules + tunnel secret
├── main.tf                           # tunnel (kept) + dns records + access
├── outputs.tf                        # tunnel_id, tunnel_token (sensitive)
├── services.tfvars.example           # single source of truth
├── services.tfvars                   # (gitignored) real services
├── backend.tfvars.example
├── terraform.tfvars.example
├── .gitignore
└── README.md
```

## Design decisions

| Topic | Decision | Reason |
|---|---|---|
| Traffic origin | **OCI Load Balancer (TCP passthrough)** | LB is already provisioned in `infra-oci-dmxyz`, TLS is terminated by Traefik, and Cloudflare proxy hides the LB IP from public DNS. The Tunnel resource is kept in TF for future use. |
| TLS termination | **Traefik (in-cluster)** with a default cert today, cert-manager-managed Let's Encrypt certs coming next | cert-manager + Cloudflare DNS-01 challenge will give us a valid cert in Traefik; until then, the LB→Traefik hop is internal (OCI VCN private IP) so the self-signed cert is fine. |
| Access identity | **Google OAuth** | Personal account, zero friction. |
| Default Access policy | **Default deny + opt-in public per service** | More secure; we set `public = true` only on what needs it. |
| State backend | **Existing OCI bucket** (`bucket-darylemb-20260125`) | Same backend as `infra-oci-dmxyz`, different key. |
| Cluster networking | **Tailscale mesh** | No port forwarding at home, free, works on macOS, MagicDNS. |
| OCI as control plane | **Yes** | 99.95% uptime vs. house power outages. |
| Domain switching | **`services.tfvars`** | One file controls all subdomains. |
| CI/CD | GitHub Actions | Plan on PR, apply on push to `main` with `environment: production`. |

## Architecture

```
                          ┌──────────────────┐
                          │  User (web)      │
                          └────────┬─────────┘
                                   │ HTTPS
                                   ▼
                          ┌──────────────────┐
                          │ Cloudflare Edge  │
                          │  TLS offload     │
                          │  DDoS (free)     │
                          │  Access (Google) │
                          └────────┬─────────┘
                                   │ HTTPS (CF→origin)
                                   ▼
                          ┌──────────────────┐
                          │ OCI Load Balancer│
                          │ k3s-public-lb    │
                          │ TCP passthrough  │
                          │  (10 Mbps free)  │
                          └────────┬─────────┘
                                   │ TLS
                          ┌────────▼─────────┐
                          │ OCI VM (k3s)     │
                          │ 10.0.0.165       │
                          │ klipper-lb NAT   │
                          │ → Traefik (svc)  │
                          │ → backend svc    │
                          └──────────────────┘
                          (Tailscale 100.64.0.0/10)
                                   ▲
                ┌──────────────────┼──────────────────┐
                │                  │                  │
         ┌────────────┐     ┌────────────┐     ┌────────────┐
         │ OCI VM     │     │ Rocky      │     │ Mac Mini   │
         │ k3s server │◄───►│ k3s agent  │◄───►│ k3s agent  │
         │ + worker   │ TS  │ Coolify    │ TS  │ Ollama/MLX │
         │ MySQL      │mesh │ apps       │mesh │            │
         │ monitoring │     │            │     │            │
         │ 24/7       │     │ standby    │     │ planned    │
         └────────────┘     └────────────┘     └────────────┘
```

A failure at home (power loss) doesn't take the control plane down — the OCI
VM keeps the API alive, and pods can reschedule to it (subject to taints and
resource availability).

## Resources created

| Resource | Name | Purpose |
|---|---|---|
| `random_id.tunnel_secret` | — | 32-byte base64 secret for the tunnel (kept for future). |
| `cloudflare_zero_trust_tunnel_cloudflared` | `k3s` | Tunnel defined in TF. **Not currently running** (no `cloudflared` DaemonSet in the cluster). |
| `cloudflare_zero_trust_tunnel_cloudflared_config` | `k3s` | Ingress rules (kept for parity with DNS records). |
| `cloudflare_dns_record` | per service | A record of each hostname → `oci_load_balancer_ip` (`proxied = true`). |
| `cloudflare_zero_trust_access_application` | `access-<service>` | Access app per service. |
| `data.cloudflare_ip_ranges` | — | Cloudflare IP ranges (for future LB allowlist). |

## `services.tfvars` — single source of truth

```hcl
services = {
  grafana = {
    hostname    = "grafana.darylm.xyz"
    service_url = "http://kube-prometheus-stack-grafana.monitoring.svc.cluster.local:80"
    public      = false  # requires Access
  }
  llm = {
    hostname    = "llm.darylm.xyz"
    service_url = "http://ollama.ai.svc.cluster.local:11434"
    public      = true   # open API
  }
  # ...
}
```

Add a subdomain = one entry. The PR triggers `terraform plan`, you review the
diff, merge, apply.

## Required GitHub secrets

`github.com/darylemb/cloudflare` → Settings → Secrets and variables → Actions:

| Secret | Description |
|---|---|
| `CLOUDFLARE_API_TOKEN` | `Zone:DNS:Edit`, `Zone:Zone:Edit`, `Account:Cloudflare Tunnel:Edit`, `Account:Access:Edit`. |
| `CLOUDFLARE_ACCOUNT_ID` | Sidebar of the dashboard. |
| `CLOUDFLARE_ZONE_ID` | Zone ID for `darylm.xyz`. |
| `OCI_TENANCY_OCID` | Same as `infra-oci-dmxyz`. |
| `OCI_USER_OCID` | Same. |
| `OCI_FINGERPRINT` | Same. |
| `OCI_COMPARTMENT_ID` | Same. |
| `OCI_API_PRIVATE_KEY` | Same. Used by the OCI backend. |
| `BACKEND_BUCKET` | `bucket-darylemb-20260125`. |
| `BACKEND_NAMESPACE` | `idkw4f4zgz2v`. |
| `BACKEND_REGION` | `us-ashburn-1`. |
| `GOOGLE_OAUTH_CLIENT_ID` | Google OAuth Client ID (from Google Cloud Console). Optional; if set, Access uses Google login instead of email OTP. |
| `GOOGLE_OAUTH_CLIENT_SECRET` | Google OAuth Client Secret. Required if `GOOGLE_OAUTH_CLIENT_ID` is set. |

## Deployment flow

### Initial bootstrap (one time, in order)

1. **Cluster networking**: see [`bootstrap/tailscale/README.md`](./bootstrap/tailscale/README.md). Install Tailscale on all nodes, approve the subnet routes, paste the ACLs.
2. **k3s install**: see [`bootstrap/k3s/README.md`](./bootstrap/k3s/README.md). Server on OCI, agents on Rocky and Mac Mini.
3. **(optional) Cloudflare Tunnel in the cluster**: see [`bootstrap/cloudflared/README.md`](./bootstrap/cloudflared/README.md). Only needed if you switch the active origin to the tunnel.
4. **Push `services.tfvars` to this repo**, push to `main`. The workflow applies the DNS records + Access apps.

### Normal operation

- **Add a service**: edit `services.tfvars`, PR, review the plan, merge → automatic apply.
- **Change destination**: same entry, modify `service_url`. Apply updates the DNS record.
- **Make a service public**: change `public = true`. Apply removes the Access app.
- **Rotate tunnel token**: taint or recreate the resource (only relevant if you turn the tunnel back on).

## GitHub Actions workflow

Same structure as `infra-oci-dmxyz`:

- **`plan` job**: on PR to `main`, writes the plan as a comment.
- **`apply` job**: on push to `main`, `terraform apply -auto-approve`, requires `environment: production`.
- **OCI backend setup**: in each job, write `~/.oci/config` + key file from secrets.

## Terraform outputs

| Output | Sensitive | Use |
|---|---|---|
| `tunnel_id` | no | Display in console / docs. |
| `tunnel_cname_target` | no | CNAME target of the tunnel (for when we turn it on). |
| `tunnel_token` | **yes** | Paste into k3s as a Secret (only if running cloudflared). |
| `services_summary` | no | Map of hostname → public/private. |

## Cost

| Component | Cost |
|---|---|
| Cloudflare (DNS, Access, Universal SSL) | **$0** |
| Tailscale (1-3 nodes, 1 user) | **$0** |
| k3s | **$0** |
| OCI free tier (A1.Flex + MySQL + 10 Mbps LB) | **$0** |
| Rocky + Mac Mini electricity (when on) | **~$3-5/month** |

**Total: ~$0-5/month.** All Cloudflare certs and Access policies are free on
the Free plan. No paid features are in use.

## Roadmap

- **cert-manager + Let's Encrypt DNS-01 challenge** (via Cloudflare API token) so Traefik has a valid cert and we can drop Cloudflare proxy if needed.
- External Secrets Operator pulling the tunnel token from Cloudflare API (no manual `kubectl create secret`).
- `cloudflare_email_routing` for `*@darylm.xyz` → Gmail.
- Cloudflare WAF custom rules (rate limit, geo block).
- WARP for mobile access to the tailnet.
- Backup of the OCI bucket state to R2.
- `open-webui` Deployment pinned to the Mac Mini.

## Local commands

```bash
terraform init -backend-config=backend.tfvars
terraform plan  -var-file=services.tfvars -var-file=terraform.tfvars
terraform apply -var-file=services.tfvars -var-file=terraform.tfvars -auto-approve
```

## Relationship with other repos

- **`infra-oci-dmxyz`**: provisions the OCI VM (compute), the **OCI Load Balancer** (k3s-public-lb, the active origin), the MySQL DB, and the bastion. The LB is the hot path for HTTP today.
- **`bootstrap/` (in this repo)**: out-of-band setup (Tailscale, k3s, cloudflared). The `cloudflared/` subdir is dormant.
- **`gitops-dmxyz`**: Argo CD that syncs k3s manifests. Hosts cert-manager, the Argo CD Application for `chroma-server`, the `kube-prometheus-stack`, `loki-stack`, and any other in-cluster apps.
- **`cloudflare` (this repo)**: DNS records (A → OCI LB) + Access apps for each service.
- **`chroma-server`**: the agent's persistent memory, lives in-cluster.
