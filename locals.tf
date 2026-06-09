locals {
  zone_id = var.cloudflare_zone_id

  tunnel_secret = random_id.tunnel_secret.b64_std

  ingress_rules = concat(
    [for k, v in var.services : {
      hostname = v.hostname
      service  = v.service_url
    }],
    [{
      hostname = null
      service  = "http_status:404"
    }]
  )
}
