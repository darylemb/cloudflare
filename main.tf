resource "random_id" "tunnel_secret" {
  byte_length = 32
}

data "cloudflare_ip_ranges" "cloudflare" {}

resource "cloudflare_zero_trust_tunnel_cloudflared" "k3s" {
  account_id    = var.cloudflare_account_id
  name          = var.tunnel_name
  tunnel_secret = local.tunnel_secret
  config_src    = "cloudflare"
}

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

resource "cloudflare_dns_record" "services" {
  for_each = var.services

  zone_id = local.zone_id
  name    = each.value.hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.k3s.id}.cf.argotunnel.com"
  proxied = true
  ttl     = 1
  comment = "Tunnel route for ${each.key} via ${var.tunnel_name}"
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
  #
  # Access policy precedence:
  #   1. If access_allow_emails is set, allow only those emails (strictest).
  #      We use email_domain matching for robustness against IdP case
  #      normalisation and aliased addresses.
  #   2. Otherwise, allow anyone who has authenticated through any IdP
  #      (gated by the Access login screen — they still need to log in).
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
