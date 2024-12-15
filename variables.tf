variable "controlplane_servers" {
  type        = map(string)
  description = "A map of controlplane hostname -> IP for controlplane nodes"
}

variable "kubelet_servers" {
  type        = map(string)
  description = "A map of kubelet hostname -> IP for worker nodes"
}

variable "ssh_user" {
  type = string
}

variable "ssh_private_key_path" {
  type = string
}

variable "etcd_version" {
  type    = string
  default = "v3.5.16"
}

variable "kubernetes_version" {
  type    = string
  default = "v1.32.0"
}

variable "cni_plugins_version" {
  type        = string
  description = "The version of the CNI plugins to install from https://github.com/containernetworking/plugins/releases/download/"
  default     = "v1.5.0"
}

variable "api_loadbalancer_host" {
  type        = string
  description = "The cluster API server load balancer host"
}

variable "api_loadbalancer_port" {
  type        = string
  description = "The cluster API server load balancer host"
  default     = "6444" # this allows for the loadbalancer to be on a control plane node
}

variable "cluster_dns_ip" {
  type        = string
  description = "value for the cluster DNS"
  default     = "10.96.0.10"
}

variable "upstream_dns_server" {
  type        = string
  description = "value for the upstream DNS server"
}

variable "cluster_pod_cidr" {
  type        = string
  description = "CIDR from which to assign pod IPs"
  default     = "10.244.0.0/16"
}

variable "cluster_service_cidr" {
  type        = string
  description = "CIDR from which to assign service IPs"
  default     = "10.96.0.0/12"
}

variable "cluster_dns_domain" {
  type        = string
  description = "value for the cluster DNS domain"
  default     = "cluster.local"
}

variable "cluster_name" {
  type = string
}

variable "etcd_cluster_state" {
  type = string
  validation {
    condition     = var.etcd_cluster_state == "new" || var.etcd_cluster_state == "existing"
    error_message = "etcd_cluster_state must be either 'new' or 'existing'"
  }
}

variable "remote_tmp_dir" {
  type    = string
  default = "/tmp/k8s"
}

variable "random_node_sleep" {
  type        = number
  description = "value in seconds to sleep before starting the node services"
  default     = 10
}

variable "coredns_version" {
  type        = string
  description = "The version of CoreDNS to install"
  default     = "1.9.4"
}

variable "flannel_cni_plugin_image_tag" {
  type        = string
  description = "The version of the flannel CNI plugin image to install"
  default     = "v1.6.0-flannel1"
}

variable "flannel_image_tag" {
  type        = string
  description = "The version of flannel to install"
  default     = "v0.26.2"
}