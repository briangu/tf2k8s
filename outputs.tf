# output info from our cluster info that we can use for etcdctl

output "etcd_endpoints" {
  value = join(",", formatlist("https://%s:2379", values(var.controlplane_servers)))
}

output "etcd_cluster_state" {
  value = var.etcd_cluster_state
}

output "etcd_cluster_name" {
  value = var.cluster_name
}

output "etcd_cluster_servers" {
  value = jsonencode(var.controlplane_servers)
}

output "etcdctl_example" {
  value = "etcdctl --endpoints=${join(",", formatlist("https://%s:2379", values(var.controlplane_servers)))} --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key endpoint health --cluster"
}

output "kubectl_example" {
  value = "./files/bin/kubectl --kubeconfig=./certs/admin.kubeconfig get namespaces"
}
