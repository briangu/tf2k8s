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
cluster_pod_cidr     = "10.244.0.0/16"
cluster_service_cidr = "10.96.0.0/12"
cluster_dns_ip       = "10.96.0.10"
cluster_dns_domain   = "cluster.local"
upstream_dns_server  = "192.168.88.1"

api_loadbalancer_host = "192.168.88.250"
api_loadbalancer_port = "6444"

etcd_version          = "v3.5.16"
kubernetes_version    = "v1.32.0"
cni_plugins_version   = "v1.5.0"
coredns_version       = "1.9.4"

# start with 'new' and then after everything is built reapply with 'existing'
etcd_cluster_state = "existing"

remote_tmp_dir = "/tmp/k8s"
