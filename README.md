# cloudflare

Manages the Cloudflare layer (DNS, Tunnel, Access) for the **dmxyz** homelab +
cloud cluster. Terraform against the Cloudflare API, deployed via GitHub
Actions, state stored in the OCI bucket.

The cluster is 3 nodes joined into one k3s cluster over a Tailscale mesh:

| Node | Where | Role |
|---|---|---|
| OCI VM (A1.Flex, Always Free) | Cloud | k3s server (control plane) + worker |
| Rocky Linux | Home | k3s agent |
| Mac Mini (Apple Silicon) | Home | k3s agent + Ollama/MLX |

Cloudflare Tunnel runs as a DaemonSet on every node, so it survives any single
node going down (including power outages at home).

---

## Layout of this repo

```
cloudflare/
├── .github/workflows/terraform.yml   # Plan on PR, apply on push to main
├── bootstrap/                        # Out-of-band setup for the cluster itself
│   ├── tailscale/                    #   Tailscale mesh (100.64.0.0/10)
│   ├── k3s/                          #   k3s server + agent install scripts
│   └── cloudflared/                  #   DaemonSet manifests for the Tunnel
├── versions.tf                       # cloudflare/cloudflare >= 5.0.0
├── provider.tf
├── variables.tf
├── locals.tf                         # ingress rules + tunnel secret
├── main.tf                           # tunnel + config + dns records + access
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
| Traffic origin | **Cloudflare Tunnel** | Hides the LB IP, TLS offload at CF, bandwidth limited by the VM (not by the 10 Mbps OCI LB free tier), native Access integration, free. |
| Access identity | **Google OAuth** | Personal account, zero friction. |
| Default Access policy | **Default deny + opt-in public per service** | More secure; we set `public = true` only on what needs it. |
| State backend | **Existing OCI bucket** (`bucket-darylemb-20260125`) | Same backend as `infra-oci-dmxyz`, different key. |
| Cluster networking | **Tailscale mesh** | No port forwarding at home, free, works on macOS, MagicDNS. |
| OCI as control plane | **Yes** | 99.95% uptime vs. house power outages. |
| Domain switching | **`services.tfvars`** | One file controls all subdomains. |
| CI/CD | GitHub Actions | Plan on PR, apply on push to `main` with `environment: production`. |

---

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
                          │  Access          │
                          └────────┬─────────┘
                                   │ Tunnel (outbound, persistent)
                ┌──────────────────┼──────────────────┐
                ▼                  ▼                  ▼
         ┌────────────┐     ┌────────────┐     ┌────────────┐
         │ OCI VM     │     │ Rocky      │     │ Mac Mini   │
         │ k3s server │◄───►│ k3s agent  │◄───►│ k3s agent  │
         │ + worker   │ TS  │ Coolify    │ TS  │ Ollama/MLX │
         │ MySQL      │mesh │ apps       │mesh │            │
         │ monitoring │     │            │     │            │
         │ 24/7       │     │ 24/7*      │     │ 24/7*      │
         └────────────┘     └────────────┘     └────────────┘
         * = when house power is on
```

A failure at home (power loss) doesn't take the control plane down — the OCI
VM keeps the API alive, and pods can reschedule to it (subject to taints and
resource availability).

---

## Resources created

| Resource | Name | Purpose |
|---|---|---|
| `random_id.tunnel_secret` | — | 32-byte base64 secret for the tunnel. |
| `cloudflare_zero_trust_tunnel_cloudflared` | `k3s` | Tunnel managed by Terraform. cloudflared in k3s connects with its token. |
| `cloudflare_zero_trust_tunnel_cloudflared_config` | `k3s` | Ingress rules: `<hostname> → <service_url>`. |
| `cloudflare_dns_record` | per service | CNAME of each hostname → tunnel. |
| `cloudflare_zero_trust_access_application` | `access-<service>` | Access app per service. |
| `cloudflare_zero_trust_access_policy` | `policy-<service>` | Default policy: allow if not public. |
| `data.cloudflare_ip_ranges` | — | Cloudflare IP ranges (for future LB allowlist). |

---

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

---

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

---

## Deployment flow

### Initial bootstrap (one time, in order)

1. **Cluster networking**: see [`bootstrap/tailscale/README.md`](./bootstrap/tailscale/README.md). Install Tailscale on all 3 nodes, approve the subnet routes, paste the ACLs.
2. **k3s install**: see [`bootstrap/k3s/README.md`](./bootstrap/k3s/README.md). Server on OCI, agents on Rocky and Mac Mini. Label the nodes.
3. **Cloudflare Tunnel in the cluster**: see [`bootstrap/cloudflared/README.md`](./bootstrap/cloudflared/README.md). Apply namespace, secret (from `terraform output -raw tunnel_token`), daemonset.
4. **Push `services.tfvars` to this repo**, push to `main`. The workflow applies the Tunnel config + DNS records + Access apps.
5. **(optional) Apply the example Ollama service** from `bootstrap/cloudflared/ollama-external-svc.yaml` if you want the LLM endpoint.

### Normal operation

- **Add a service**: edit `services.tfvars`, PR, review the plan, merge → automatic apply.
- **Change destination**: same entry, modify `service_url`. Apply updates the tunnel ingress.
- **Make a service public**: change `public = true`. Apply removes the Access app.
- **Rotate tunnel token**: taint or recreate the resource.

---

## GitHub Actions workflow

Same structure as `infra-oci-dmxyz`:

- **`plan` job**: on PR to `main`, writes the plan as a comment.
- **`apply` job**: on push to `main`, `terraform apply -auto-approve`, requires `environment: production`.
- **OCI backend setup**: in each job, write `~/.oci/config` + key file from secrets.

---

## Terraform outputs

| Output | Sensitive | Use |
|---|---|---|
| `tunnel_id` | no | Display in console / docs. |
| `tunnel_cname_target` | no | CNAME target of the tunnel. |
| `tunnel_token` | **yes** | Paste into k3s as a Secret (see bootstrap/cloudflared). |
| `services_summary` | no | Map of hostname → public/private. |

---

## Cost

| Component | Cost |
|---|---|
| Cloudflare (Tunnel, DNS, Access) | **$0** |
| Tailscale (3 nodes, 1 user) | **$0** |
| k3s | **$0** |
| OCI free tier (A1.Flex + MySQL) | **$0** |
| Rocky + Mac Mini electricity (always on) | **~$3-5/month** |

**Total: ~$0-5/month.**

---

## Roadmap

- External Secrets Operator pulling the tunnel token from Cloudflare API (no manual `kubectl create secret`).
- `cloudflare_email_routing` for `*@darylm.xyz` → Gmail.
- Cloudflare WAF custom rules (rate limit, geo block).
- WARP for mobile access to the tailnet.
- Backup of the OCI bucket state to R2.
- `open-webui` Deployment pinned to the Mac Mini.

---

## Local commands

```bash
terraform init -backend-config=backend.tfvars
terraform plan  -var-file=services.tfvars -var-file=terraform.tfvars
terraform apply -var-file=services.tfvars -var-file=terraform.tfvars -auto-approve
```

---

## Relationship with other repos

- **`infra-oci-dmxyz`**: provisions the OCI VM (compute, LB, MySQL, bastion). The LB is no longer in the hot path for HTTP — Tunnel takes that role. LB can stay for SSH/bastion.
- **`bootstrap/` (in this repo)**: out-of-band setup (Tailscale, k3s, cloudflared). Lives in this repo because the cluster exists to serve the Tunnel.
- **`gitops-dmxyz`** (or equivalent): ArgoCD/Flux that syncs k3s manifests. Add the `cloudflared` DaemonSet, the `ollama` Endpoints, and the workloads.
- **`cloudflare` (this repo)**: DNS, Tunnel, Access, WAF.
