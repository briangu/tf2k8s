# tf2k8s

# Overview

TF2K8S is a single-file (ish) terraform configuration for deploying the k8s control plane and workers from scratch, without using kubeadm and generating all certs.

This is mainly for educational purposes or homelab setups where you have total control and security isn't your main concern.  By building everything from scratch the entire process that's hidden behind tools like kubeadm are more obvious and it's a way to see the interconnectedness of the sub-systems.

Networking is the most complex part of this and it is solved with a combo of Flannel CNI and CoreDNS.

# Requirements

## SSH access

The server that terraform launches from must have ssh access to all targets.

```bash
ssh-copy-id <host>
```

2. User SUDO access

The ssh user on the remote target machines must have sudo access.

```
ssh user@host
sudo visudo

# very low security but convenient solution
<username>   ALL=(ALL) NOPASSWD:ALL
```




# Usage

Setup your configs in terraform.tfvars.  Namely, you'll need to specify

```
ssh_private_key_path = "~/.ssh/id_ed25519"
ssh_user = "ubuntu"
```

Choose your control plane and worker servers.

```
controlplane_servers = {
    homelab-1 = "192.168.88.250"
    homelab-2 = "192.168.88.246"
    homelab-3 = "192.168.88.248"
}

kubelet_servers = {
    homelab-4 = "192.168.88.247"
    homelab-5 = "192.168.88.249"
    homelab-6 = "192.168.88.245",
    homelab-7 = "192.168.88.244",
    homelab-8 = "192.168.88.243",
    homelab-9 = "192.168.88.242",
}

cluster_name         = "homelab"
```

You may want to adjust which server is your API server loadbalancer.  In the simple case, we let the first control plane node also be the load balancer:

```
api_loadbalancer_host = "192.168.88.250"
api_loadbalancer_port = "6444"
```

You'll need this to be `new` when you first deploy and then redeploy with `existing` immediately after a successful build of your control plane.

```
etcd_cluster_state = "existing"
```

You probably don't need to change these:

```
cluster_pod_cidr     = "10.244.0.0/16"
cluster_service_cidr = "10.96.0.0/12"
cluster_dns_ip       = "10.96.0.10"
cluster_dns_domain   = "cluster.local"

etcd_version          = "v3.5.16"
kubernetes_version    = "v1.32.0"
cni_plugins_version   = "v1.5.0"
coredns_version       = "1.9.4"

remote_tmp_dir = "/tmp/k8s"

```

Deployment is done via the typical terraform cycle:


```bash
$ terraform apply
```

# Maintaining the cluster after initial deployment.

There are triggers in the terraform which try their best to detect what needs to be redeployed, but you can always do taints to force a specific scenario or node to be updated:

For example, if you wanted to redeploy a specific kubelet you could do the following:

```bash
terraform taint 'null_resource.provision_kubelets["homelab-7"]'
terraform apply
```

