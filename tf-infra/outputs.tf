output "node_mlb_ranges" {
  description = "mlb /24 routed to each node (alias IP range)"
  value       = zipmap(google_compute_instance.mk8s[*].name, local.node_mlb_ranges)
}

output "lb_ip" {
  description = "Public IP of the external proxy Network Load Balancer"
  value       = google_compute_global_address.lb.address
}
