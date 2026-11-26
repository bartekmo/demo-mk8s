output "node_mlb_ranges" {
  description = "mlb /24 routed to each node (alias IP range)"
  value       = zipmap(google_compute_instance.mk8s[*].name, local.node_mlb_ranges)
}

output "lb_ip" {
  description = "Public IP of the external proxy Network Load Balancer"
  value       = google_compute_global_address.lb.address
}

output "argocd_url" {
  description = "Argo CD UI (create DNS A record argocd.<dns_root> -> lb_ip)"
  value       = "https://argocd.${var.dns_root}"
}

output "authentik_url" {
  description = "authentik IdP (create DNS A record auth.<dns_root> -> lb_ip)"
  value       = "https://auth.${var.dns_root}"
}

output "get_passwords" {
  description = "Run on node-0 to read the in-cluster generated passwords"
  value       = <<-EOT
    microk8s kubectl -n authentik get secret authentik-bootstrap -o jsonpath='{.data.demo-password}' | base64 -d     # user: demo
    microk8s kubectl -n authentik get secret authentik-bootstrap -o jsonpath='{.data.akadmin-password}' | base64 -d  # user: akadmin
    microk8s kubectl -n gitlab get secret gitlab-bootstrap -o jsonpath='{.data.root-password}' | base64 -d          # GitLab user: root
  EOT
}

output "gitlab_url" {
  description = "GitLab (DNS: gitlab.<dns_root> and registry.<dns_root> -> lb_ip; SSH on lb_ip:22)"
  value       = "https://gitlab.${var.dns_root}"
}
