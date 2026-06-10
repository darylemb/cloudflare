zone_name = "darylm.xyz"

# All services below are exposed via the Cloudflare Tunnel that runs as a
# DaemonSet in the k3s cluster. Each service_url must resolve from inside
# the cluster (Service ClusterIP, ExternalName, or Endpoints).
#
# Topology:
#   OCI VM   = control plane, MySQL, monitoring (24/7)
#   Rocky    = Coolify + home apps
#   Mac Mini = Ollama (qwen3.5:4b MLX) + ML workloads

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

  argocd = {
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
