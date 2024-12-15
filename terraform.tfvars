ssh_private_key_path = "~/.ssh/id_ed25519"
ssh_user = "brian"

controlplane_servers = {
    parallac-1 = "192.168.88.250"
    parallac-2 = "192.168.88.246"
    parallac-3 = "192.168.88.248"
    parallac-4 = "192.168.88.247"
    parallac-5 = "192.168.88.249"
}

kubelet_servers = {
  "parallac-6" = "192.168.88.245",
  "parallac-7" = "192.168.88.244",
  "parallac-8" = "192.168.88.243",
  "parallac-9" = "192.168.88.242",
}

cluster_name         = "parallac"
upstream_dns_server  = "192.168.88.1"

api_loadbalancer_host = "192.168.88.250"

# start with 'new' and then after everything is built reapply with 'existing'
etcd_cluster_state = "existing"
