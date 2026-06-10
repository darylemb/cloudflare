resource "random_id" "tunnel_secret" {
  byte_length = 32
}

data "cloudflare_ip_ranges" "cloudflare" {}

# Cloudflare Tunnel — kept as a resource so we have the credentials and can
# route to it in the future (e.g. for non-HTTP services or to hide IPs).
# Currently we use DNS A records for HTTP because CNAMEs to cf.argotunnel.com
# trigger error 1014 (CNAME Cross-User Banned) on the Free plan.
resource "cloudflare_zero_trust_tunnel_cloudflared" "k3s" {
  account_id    = var.cloudflare_account_id
  name          = var.tunnel_name
  tunnel_secret = local.tunnel_secret
  config_src    = "cloudflare"
}

# Optional tunnel config (used when cloudflared is running somewhere).
# Even with the A-record DNS approach, having the tunnel defined lets us
# enable cloudflared on individual nodes later without redoing the Terraform.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "k3s" {
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.k3s.id
  account_id = var.cloudflare_account_id

  config = {
    ingress = [
      for rule in local.ingress_rules : {
        hostname = rule.hostname
        service  = rule.service
      }
    ]
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "k3s" {
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.k3s.id
  account_id = var.cloudflare_account_id
}

variable "oci_load_balancer_ip" {
  description = "Public IP of the OCI load balancer (used for DNS A records)."
  type        = string
}

resource "cloudflare_dns_record" "services" {
  for_each = var.services

  zone_id = local.zone_id
  name    = each.value.hostname
  type    = "A"
  content = var.oci_load_balancer_ip
  proxied = true
  ttl     = 1
  comment = "Route for ${each.key} via OCI LB (A record)"
}

resource "cloudflare_zero_trust_access_application" "services" {
  for_each = {
    for k, v in var.services : k => v if !v.public
  }

  zone_id          = local.zone_id
  name             = "access-${each.key}"
  domain           = each.value.hostname
  type             = "self_hosted"
  session_duration = var.access_session_duration

  # Inline policies (provider v5 requires policies inside the application
  # resource, not as separate cloudflare_zero_trust_access_policy resources
  # — those don't have an application_id field and end up orphaned).
  policies = length(var.access_allow_emails) > 0 ? [
    {
      name       = "policy-${each.key}"
      decision   = "allow"
      precedence = 1
      include = [
        for email in var.access_allow_emails : {
          email_domain = { domain = split("@", email)[1] }
        }
      ]
    }
    ] : [
    {
      name       = "policy-${each.key}"
      decision   = "allow"
      precedence = 1
      include = [
        {
          everyone = {}
        }
      ]
    }
  ]
}

resource "cloudflare_zero_trust_access_identity_provider" "google" {
  count = var.google_oauth_client_id != null ? 1 : 0

  account_id = var.cloudflare_account_id
  name       = "google-oauth"
  type       = "google"

  config = {
    client_id     = var.google_oauth_client_id
    client_secret = var.google_oauth_client_secret
  }
}
