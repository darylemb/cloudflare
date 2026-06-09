variable "cloudflare_api_token" {
  description = "Cloudflare API token with Tunnel, DNS, and Access edit permissions"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for the zone"
  type        = string
  sensitive   = true
}

variable "tunnel_name" {
  description = "Name of the Cloudflare Tunnel"
  type        = string
  default     = "k3s-tunnel"
}

variable "access_session_duration" {
  description = "Duration of Access session (e.g. 24h, 30m)"
  type        = string
  default     = "24h"
}

variable "google_oauth_client_id" {
  description = "Google OAuth Client ID configured as Access identity provider"
  type        = string
  sensitive   = true
  default     = null
}

variable "google_oauth_client_secret" {
  description = "Google OAuth Client Secret configured as Access identity provider"
  type        = string
  sensitive   = true
  default     = null
}

variable "access_allow_emails" {
  description = "List of emails allowed through Access (when google_oauth_client_id is set, this is used for the policy include rule)"
  type        = list(string)
  default     = []
}

variable "services" {
  description = "Map of services exposed via the tunnel. Key is an arbitrary slug."
  type = map(object({
    hostname    = string
    service_url = string
    public      = bool
  }))
  default = {}
}
