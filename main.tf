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
}

resource "cloudflare_zero_trust_access_policy" "services" {
  for_each = {
    for k, v in var.services : k => v if !v.public
  }

  account_id = var.cloudflare_account_id
  name       = "policy-${each.key}"
  decision   = "allow"

  # If a Google IdP is configured and access_allow_emails is set, restrict
  # to those emails. Otherwise allow everyone (still gated by Access login).
  include = length(var.access_allow_emails) > 0 ? [
    for email in var.access_allow_emails : {
      email = { email = email }
    }
    ] : [
    {
      everyone = {}
    }
  ]

  depends_on = [cloudflare_zero_trust_access_application.services]
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
