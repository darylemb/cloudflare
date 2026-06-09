output "tunnel_id" {
  description = "Cloudflare Tunnel ID"
  value       = cloudflare_zero_trust_tunnel_cloudflared.k3s.id
}

output "tunnel_cname_target" {
  description = "CNAME target for DNS records pointing at the tunnel"
  value       = "${cloudflare_zero_trust_tunnel_cloudflared.k3s.id}.cf.argotunnel.com"
}

output "tunnel_token" {
  description = "Token for the cloudflared DaemonSet. Pass to k3s as a Secret."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.k3s.token
  sensitive   = true
}

output "services_summary" {
  description = "Map of exposed services with their public/private status"
  value = {
    for k, v in var.services :
    k => {
      hostname = v.hostname
      public   = v.public
    }
  }
}
