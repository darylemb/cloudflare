zone_name = "darylm.xyz"

# All services below are exposed via Cloudflare proxy + OCI Load Balancer.
# Each hostname has an A record pointing at oci_load_balancer_ip (set in
# terraform.tfvars), proxied=true. Cloudflare edge terminates TLS, Access
# enforces auth, and the OCI LB (k3s-public-lb) does TCP passthrough to
# the k3s nodes on 10.0.0.165:80/:443 where Traefik routes to the
# in-cluster services.
#
# Topology:
#   OCI VM   = control plane, MySQL, monitoring (24/7)
#   Rocky    = standby (rejoin when needed)
#   Mac Mini = planned (Ollama/MLX)

# Emails allowed to log in to non-public services. If empty, any validated
# Google account can log in (when the Google IdP is configured).
access_allow_emails = [
  "darylemb@gmail.com",
]

services = {
  # ---- OCI VM (prefers to run here) ----
  grafana = {
    hostname    = "grafana.darylm.xyz"
    service_url = "http://kube-prometheus-stack-grafana.monitoring.svc.cluster.local:80"
    public      = false
  }

  prometheus = {
    hostname    = "prom.darylm.xyz"
    service_url = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"
    public      = false
  }

  argo = {
    hostname    = "argo.darylm.xyz"
    service_url = "http://argocd-server.argocd.svc.cluster.local:80"
    public      = false
  }

  uptime = {
    hostname    = "uptime.darylm.xyz"
    service_url = "http://uptime-kuma.monitoring.svc.cluster.local:3001"
    public      = false
  }

  # ---- Rocky (home) ----
  coolify = {
    hostname    = "coolify.darylm.xyz"
    service_url = "http://coolify.kube-system.svc.cluster.local:8000"
    public      = false
  }

  # ---- Mac Mini (home, LLM + ML) ----
  llm = {
    hostname    = "llm.darylm.xyz"
    service_url = "http://ollama.ai.svc.cluster.local:11434"
    public      = true
  }

  chat = {
    hostname    = "chat.darylm.xyz"
    service_url = "http://open-webui.ai.svc.cluster.local:8080"
    public      = false
  }
}
