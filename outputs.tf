output "tunnel_id" {
  description = "Cloudflare Tunnel ID (kept for future use; current DNS uses A records)"
  value       = cloudflare_zero_trust_tunnel_cloudflared.k3s.id
}

output "tunnel_token" {
  description = "Token for the cloudflared DaemonSet. Pass to k3s as a Secret."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.k3s.token
  sensitive   = true
}

output "oci_load_balancer_ip" {
  description = "OCI LB public IP that A records point to"
  value       = var.oci_load_balancer_ip
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
