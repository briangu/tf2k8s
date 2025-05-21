terraform {
  required_providers {
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.0.0"
}

provider "tls" {}

locals {
  controlplane_hostnames = keys(var.controlplane_servers)

  api_loadbalancer_url = "https://${var.api_loadbalancer_host}:${var.api_loadbalancer_port}"
}


# ===================================================================
# ROOT CA (MAIN CLUSTER CA)
# ===================================================================
resource "tls_private_key" "ca_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "ca_cert" {
  private_key_pem       = tls_private_key.ca_key.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 87600 # ~10 years
  early_renewal_hours   = 720
  allowed_uses = [
    "cert_signing",
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth"
  ]

  subject {
    common_name  = "kubernetes"
    organization = "Kubernetes"
  }
}

# ===================================================================
# ETCD CA
# ===================================================================
resource "tls_private_key" "etcd_ca_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "etcd_ca_cert" {
  private_key_pem       = tls_private_key.etcd_ca_key.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 87600
  early_renewal_hours   = 720
  allowed_uses = [
    "cert_signing",
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth"
  ]

  subject {
    common_name  = "etcd-ca"
    organization = "etcd"
  }
}


# ===================================================================
# SERVICE ACCOUNT KEY PAIR
# This is just a key pair for signing service account tokens.
# ===================================================================
resource "tls_private_key" "sa_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}


# ===================================================================
# APISERVER CERTIFICATE (signed by ROOT CA)
# Subject: CN=kube-apiserver
# DNS names and IP addresses should include the hostnames and
# cluster IP for the API server load balancer or the control-plane node IPs.
# ===================================================================
resource "tls_private_key" "apiserver_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "apiserver_csr" {
  private_key_pem = tls_private_key.apiserver_key.private_key_pem
  subject {
    common_name  = "kube-apiserver"
    organization = "Kubernetes"
  }

  dns_names    = concat(local.controlplane_hostnames, ["kubernetes", "kubernetes.default", "kubernetes.default.svc", "kubernetes.default.svc.${var.cluster_dns_domain}"])
  ip_addresses = concat([for h in local.controlplane_hostnames : var.controlplane_servers[h]], [cidrhost(var.cluster_service_cidr, 1)])
}

resource "tls_locally_signed_cert" "apiserver_cert" {
  cert_request_pem      = tls_cert_request.apiserver_csr.cert_request_pem
  ca_cert_pem           = tls_self_signed_cert.ca_cert.cert_pem
  ca_private_key_pem    = tls_private_key.ca_key.private_key_pem
  validity_period_hours = 8760
  early_renewal_hours   = 720
  allowed_uses = [
    "server_auth",
    "key_encipherment",
    "digital_signature"
  ]
}

# ===================================================================
# CONTROLLER-MANAGER CERT (signed by ROOT CA)
# Subject: CN=system:kube-controller-manager, O=system:kube-controller-manager
# Used by the controller manager to authenticate to the API server.
# ===================================================================

resource "tls_private_key" "controller_manager_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "controller_manager_csr" {
  private_key_pem = tls_private_key.controller_manager_key.private_key_pem
  subject {
    common_name  = "system:kube-controller-manager"
    organization = "system:kube-controller-manager"
  }
}

resource "tls_locally_signed_cert" "controller_manager_cert" {
  cert_request_pem      = tls_cert_request.controller_manager_csr.cert_request_pem
  ca_cert_pem           = tls_self_signed_cert.ca_cert.cert_pem
  ca_private_key_pem    = tls_private_key.ca_key.private_key_pem
  validity_period_hours = 8760
  early_renewal_hours   = 720
  allowed_uses = [
    "client_auth",
    "key_encipherment",
    "digital_signature"
  ]
}

# ===================================================================
# KUBE-SCHEDULER CERT (signed by ROOT CA)
# Subject: CN=system:kube-scheduler, O=system:masters
# Used by the scheduler to authenticate to the API server.
# ===================================================================

resource "tls_private_key" "scheduler_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "scheduler_csr" {
  private_key_pem = tls_private_key.scheduler_key.private_key_pem
  subject {
    # The kube-scheduler user must be "system:kube-scheduler"
    # with no organization required for scheduler
    common_name = "system:kube-scheduler"
  }
}

resource "tls_locally_signed_cert" "scheduler_cert" {
  cert_request_pem      = tls_cert_request.scheduler_csr.cert_request_pem
  ca_cert_pem           = tls_self_signed_cert.ca_cert.cert_pem
  ca_private_key_pem    = tls_private_key.ca_key.private_key_pem
  validity_period_hours = 8760
  early_renewal_hours   = 720
  allowed_uses = [
    "client_auth",
    "key_encipherment",
    "digital_signature"
  ]
}


# ===================================================================
# APISERVER-KUBELET-CLIENT CERT (client cert signed by ROOT CA)
# Subject: CN=system:apiserver-kubelet-client, O=system:masters
# This is the apiserver client cert for talking to kubelets.
# ===================================================================
resource "tls_private_key" "apiserver_kubelet_client_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "apiserver_kubelet_client_csr" {
  private_key_pem = tls_private_key.apiserver_kubelet_client_key.private_key_pem
  subject {
    common_name  = "system:apiserver-kubelet-client"
    organization = "system:masters"
  }
}

resource "tls_locally_signed_cert" "apiserver_kubelet_client_cert" {
  cert_request_pem      = tls_cert_request.apiserver_kubelet_client_csr.cert_request_pem
  ca_cert_pem           = tls_self_signed_cert.ca_cert.cert_pem
  ca_private_key_pem    = tls_private_key.ca_key.private_key_pem
  validity_period_hours = 8760
  early_renewal_hours   = 720
  allowed_uses = [
    "client_auth",
    "key_encipherment",
    "digital_signature"
  ]
}

# ===================================================================
# APISERVER-ETCD-CLIENT CERT (client cert signed by ETCD CA)
# Subject: CN=apiserver-etcd-client, O=etcd
# Used by the apiserver to authenticate against etcd
# ===================================================================
resource "tls_private_key" "apiserver_etcd_client_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "apiserver_etcd_client_csr" {
  private_key_pem = tls_private_key.apiserver_etcd_client_key.private_key_pem
  subject {
    common_name  = "apiserver-etcd-client"
    organization = "etcd"
  }
}

resource "tls_locally_signed_cert" "apiserver_etcd_client_cert" {
  cert_request_pem      = tls_cert_request.apiserver_etcd_client_csr.cert_request_pem
  ca_cert_pem           = tls_self_signed_cert.etcd_ca_cert.cert_pem
  ca_private_key_pem    = tls_private_key.etcd_ca_key.private_key_pem
  validity_period_hours = 8760
  early_renewal_hours   = 720
  allowed_uses = [
    "client_auth",
    "key_encipherment",
    "digital_signature"
  ]
}


# ===================================================================
# ETCD SERVER CERT (signed by ETCD CA)
# Subject: CN=etcd
# DNS/IP as needed for etcd server endpoints.
# ===================================================================
resource "tls_private_key" "etcd_server_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "etcd_server_csr" {
  private_key_pem = tls_private_key.etcd_server_key.private_key_pem
  subject {
    common_name  = "etcd"
    organization = "etcd"
  }

  dns_names    = local.controlplane_hostnames
  ip_addresses = [for h in local.controlplane_hostnames : var.controlplane_servers[h]]
}

resource "tls_locally_signed_cert" "etcd_server_cert" {
  cert_request_pem      = tls_cert_request.etcd_server_csr.cert_request_pem
  ca_cert_pem           = tls_self_signed_cert.etcd_ca_cert.cert_pem
  ca_private_key_pem    = tls_private_key.etcd_ca_key.private_key_pem
  validity_period_hours = 8760
  early_renewal_hours   = 720
  allowed_uses = [
    "server_auth",
    "client_auth", # etcd server needs to authenticate to other etcd servers
    "key_encipherment",
    "digital_signature"
  ]
}

# ===================================================================
# ETCD PEER CERT (signed by ETCD CA)
# Subject: CN=etcd-peer
# Used for etcd peer-to-peer communication
# ===================================================================
resource "tls_private_key" "etcd_peer_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "etcd_peer_csr" {
  private_key_pem = tls_private_key.etcd_peer_key.private_key_pem
  subject {
    common_name  = "etcd-peer"
    organization = "etcd"
  }

  dns_names    = local.controlplane_hostnames
  ip_addresses = [for h in local.controlplane_hostnames : var.controlplane_servers[h]]
}

resource "tls_locally_signed_cert" "etcd_peer_cert" {
  cert_request_pem      = tls_cert_request.etcd_peer_csr.cert_request_pem
  ca_cert_pem           = tls_self_signed_cert.etcd_ca_cert.cert_pem
  ca_private_key_pem    = tls_private_key.etcd_ca_key.private_key_pem
  validity_period_hours = 8760
  early_renewal_hours   = 720
  allowed_uses = [
    "server_auth",
    "client_auth",
    "key_encipherment",
    "digital_signature"
  ]
}

# ===================================================================
# ETCD HEALTHCHECK-CLIENT CERT (signed by ETCD CA)
# Subject: CN=kube-etcd-healthcheck-client, O=etcd
# Used for health checks against etcd.
# ===================================================================
resource "tls_private_key" "etcd_healthcheck_client_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "etcd_healthcheck_client_csr" {
  private_key_pem = tls_private_key.etcd_healthcheck_client_key.private_key_pem
  subject {
    common_name  = "kube-etcd-healthcheck-client"
    organization = "etcd"
  }
}

resource "tls_locally_signed_cert" "etcd_healthcheck_client_cert" {
  cert_request_pem      = tls_cert_request.etcd_healthcheck_client_csr.cert_request_pem
  ca_cert_pem           = tls_self_signed_cert.etcd_ca_cert.cert_pem
  ca_private_key_pem    = tls_private_key.etcd_ca_key.private_key_pem
  validity_period_hours = 8760
  early_renewal_hours   = 720
  allowed_uses = [
    "client_auth",
    "key_encipherment",
    "digital_signature"
  ]
}

# ===================================================================
# KUBELET CERTIFICATE (signed by ROOT CA)
# Subject: CN=kubelet
# DNS names and IP addresses should include the hostnames and
# cluster IP for the API server load balancer or the control-plane node IPs.
# ===================================================================
resource "tls_private_key" "kubelet_server_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "kubelet_server_csr" {
  private_key_pem = tls_private_key.kubelet_server_key.private_key_pem
  subject {
    common_name  = "kubelet"
    organization = "Kubernetes"
  }

  dns_names    = local.controlplane_hostnames
  ip_addresses = [for h in local.controlplane_hostnames : var.controlplane_servers[h]]
}

resource "tls_locally_signed_cert" "kubelet_server_cert" {
  cert_request_pem      = tls_cert_request.kubelet_server_csr.cert_request_pem
  ca_cert_pem           = tls_self_signed_cert.ca_cert.cert_pem
  ca_private_key_pem    = tls_private_key.ca_key.private_key_pem
  validity_period_hours = 8760
  early_renewal_hours   = 720
  allowed_uses = [
    "server_auth",
    "key_encipherment",
    "digital_signature"
  ]
}

# ===================================================================
# ADMIN CERT (signed by ROOT CA)
# Subject: CN=admin, O=system:masters
# Used for admin access to the cluster.
# ===================================================================
resource "tls_private_key" "admin_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "admin_csr" {
  private_key_pem = tls_private_key.admin_key.private_key_pem
  subject {
    common_name  = "admin"
    organization = "system:masters"
  }
}

resource "tls_locally_signed_cert" "admin_cert" {
  cert_request_pem      = tls_cert_request.admin_csr.cert_request_pem
  ca_cert_pem           = tls_self_signed_cert.ca_cert.cert_pem
  ca_private_key_pem    = tls_private_key.ca_key.private_key_pem
  validity_period_hours = 8760
  early_renewal_hours   = 720
  allowed_uses = [
    "client_auth",
    "key_encipherment",
    "digital_signature"
  ]
}

# ===================================================================
# LOCAL FILE OUTPUTS FOR REFERENCE
# ===================================================================
# Root CA
resource "local_file" "ca_cert_pem" {
  content  = tls_self_signed_cert.ca_cert.cert_pem
  filename = "${path.module}/certs/ca.crt"
}

resource "local_file" "ca_key_pem" {
  content  = tls_private_key.ca_key.private_key_pem
  filename = "${path.module}/certs/ca.key"
}

# ETCD CA
resource "local_file" "etcd_ca_cert_pem" {
  content  = tls_self_signed_cert.etcd_ca_cert.cert_pem
  filename = "${path.module}/certs/etcd/ca.crt"
}

resource "local_file" "etcd_ca_key_pem" {
  content  = tls_private_key.etcd_ca_key.private_key_pem
  filename = "${path.module}/certs/etcd/ca.key"
}

# Apiserver
resource "local_file" "apiserver_key_pem" {
  content  = tls_private_key.apiserver_key.private_key_pem
  filename = "${path.module}/certs/apiserver.key"
}

resource "local_file" "apiserver_cert_pem" {
  content  = tls_locally_signed_cert.apiserver_cert.cert_pem
  filename = "${path.module}/certs/apiserver.crt"
}

# Apiserver-kubelet-client
resource "local_file" "apiserver_kubelet_client_key_pem" {
  content  = tls_private_key.apiserver_kubelet_client_key.private_key_pem
  filename = "${path.module}/certs/apiserver-kubelet-client.key"
}

resource "local_file" "apiserver_kubelet_client_cert_pem" {
  content  = tls_locally_signed_cert.apiserver_kubelet_client_cert.cert_pem
  filename = "${path.module}/certs/apiserver-kubelet-client.crt"
}

# Apiserver-etcd-client
resource "local_file" "apiserver_etcd_client_key_pem" {
  content  = tls_private_key.apiserver_etcd_client_key.private_key_pem
  filename = "${path.module}/certs/apiserver-etcd-client.key"
}

resource "local_file" "apiserver_etcd_client_cert_pem" {
  content  = tls_locally_signed_cert.apiserver_etcd_client_cert.cert_pem
  filename = "${path.module}/certs/apiserver-etcd-client.crt"
}

# ETCD server
resource "local_file" "etcd_server_key_pem" {
  content  = tls_private_key.etcd_server_key.private_key_pem
  filename = "${path.module}/certs/etcd/server.key"
}

resource "local_file" "etcd_server_cert_pem" {
  content  = tls_locally_signed_cert.etcd_server_cert.cert_pem
  filename = "${path.module}/certs/etcd/server.crt"
}

# ETCD peer
resource "local_file" "etcd_peer_key_pem" {
  content  = tls_private_key.etcd_peer_key.private_key_pem
  filename = "${path.module}/certs/etcd/peer.key"
}

resource "local_file" "etcd_peer_cert_pem" {
  content  = tls_locally_signed_cert.etcd_peer_cert.cert_pem
  filename = "${path.module}/certs/etcd/peer.crt"
}

# ETCD healthcheck-client
resource "local_file" "etcd_healthcheck_client_key_pem" {
  content  = tls_private_key.etcd_healthcheck_client_key.private_key_pem
  filename = "${path.module}/certs/etcd/healthcheck-client.key"
}

resource "local_file" "etcd_healthcheck_client_cert_pem" {
  content  = tls_locally_signed_cert.etcd_healthcheck_client_cert.cert_pem
  filename = "${path.module}/certs/etcd/healthcheck-client.crt"
}

# Kubelet

resource "local_file" "kubelet_server_key_pem" {
  content  = tls_private_key.kubelet_server_key.private_key_pem
  filename = "${path.module}/certs/kubelet.key"
}

resource "local_file" "kubelet_server_cert_pem" {
  content  = tls_locally_signed_cert.kubelet_server_cert.cert_pem
  filename = "${path.module}/certs/kubelet.crt"
}

# Service account keys
resource "local_file" "admin_key_pem" {
  content  = tls_private_key.admin_key.private_key_pem
  filename = "${path.module}/certs/admin.key"
}

resource "local_file" "admin_cert_pem" {
  content  = tls_locally_signed_cert.admin_cert.cert_pem
  filename = "${path.module}/certs/admin.crt"
}

resource "local_file" "sa_key_pem" {
  content  = tls_private_key.sa_key.private_key_pem
  filename = "${path.module}/certs/sa.key"
}
resource "local_file" "sa_pub_pem" {
  content  = tls_private_key.sa_key.public_key_pem
  filename = "${path.module}/certs/sa.pub"
}


# ===================================================================
# Control Plane Services
# ===================================================================

locals {
  etcd_service = templatefile("${path.module}/templates/etcd.service.tmpl", {
    etcd_version = var.etcd_version
  })

  kube_apiserver_service = templatefile("${path.module}/templates/kube-apiserver.service.tmpl", {
    kubernetes_version       = var.kubernetes_version
    service_cluster_ip_range = "10.96.0.0/12"
    advertise_address        = var.api_loadbalancer_host
    etcd_servers = join(",", [
      for h in local.controlplane_hostnames : "https://${var.controlplane_servers[h]}:2379"
    ])
  })
  kube_apiserver_config = templatefile("${path.module}/templates/kube-apiserver-config.yaml.tmpl", {
    service_cluster_ip_range = "10.96.0.0/12"
    etcd_servers = join(",", [
      for h in local.controlplane_hostnames : "${h}=https://${var.controlplane_servers[h]}:2379"
    ])
    cluster_pod_cidr     = var.cluster_pod_cidr
    cluster_service_cidr = var.cluster_service_cidr
    cluster_dns_domain   = var.cluster_dns_domain
    cluster_ip           = var.api_loadbalancer_host
    cluster_name         = var.cluster_name
  })

  kube_controller_manager_service = templatefile("${path.module}/templates/kube-controller-manager.service.tmpl", {
    kubernetes_version = var.kubernetes_version
    cluster_pod_cidr   = var.cluster_pod_cidr
    cluster_name       = var.cluster_name
  })
  kube_controller_manager_kubeconfig = templatefile("${path.module}/templates/controller-manager.kubeconfig.tmpl", {
    cluster_name = var.cluster_name
    server       = local.api_loadbalancer_url
    ca_cert      = tls_self_signed_cert.ca_cert.cert_pem
    client_cert  = tls_locally_signed_cert.controller_manager_cert.cert_pem
    client_key   = tls_private_key.controller_manager_key.private_key_pem
  })

  kube_scheduler_service = templatefile("${path.module}/templates/kube-scheduler.service.tmpl", {
    kubernetes_version = var.kubernetes_version
  })
  kube_scheduler_kubeconfig = templatefile("${path.module}/templates/scheduler.kubeconfig.tmpl", {
    cluster_name = var.cluster_name
    server       = local.api_loadbalancer_url
    ca_cert      = tls_self_signed_cert.ca_cert.cert_pem
    client_cert  = tls_locally_signed_cert.scheduler_cert.cert_pem
    client_key   = tls_private_key.scheduler_key.private_key_pem
  })
}

resource "local_file" "admin_kubeconfig" {
  content = templatefile("${path.module}/templates/admin.kubeconfig.tmpl", {
    cluster_name = var.cluster_name
    server       = local.api_loadbalancer_url
    ca_cert      = tls_self_signed_cert.ca_cert.cert_pem
    client_cert  = tls_locally_signed_cert.admin_cert.cert_pem
    client_key   = tls_private_key.admin_key.private_key_pem
  })
  filename = "${path.module}/certs/admin.kubeconfig"
}

resource "null_resource" "download_k8s_binaries" {
  triggers = {
    kubernetes_version = var.kubernetes_version
    etcd_version       = var.etcd_version
  }

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p files/bin
      curl -L "https://dl.k8s.io/release/${var.kubernetes_version}/bin/linux/amd64/kube-apiserver" -o files/bin/kube-apiserver
      curl -L "https://dl.k8s.io/release/${var.kubernetes_version}/bin/linux/amd64/kube-controller-manager" -o files/bin/kube-controller-manager
      curl -L "https://dl.k8s.io/release/${var.kubernetes_version}/bin/linux/amd64/kube-scheduler" -o files/bin/kube-scheduler
      curl -L "https://dl.k8s.io/release/${var.kubernetes_version}/bin/linux/amd64/kubectl" -o files/bin/kubectl
      curl -L "https://dl.k8s.io/release/${var.kubernetes_version}/bin/linux/amd64/kubelet" -o files/bin/kubelet

      chmod +x files/bin/*

      # Download etcd and etcdctl
      curl -L "https://github.com/etcd-io/etcd/releases/download/${var.etcd_version}/etcd-${var.etcd_version}-linux-amd64.tar.gz" \
        -o files/bin/etcd-${var.etcd_version}-linux-amd64.tar.gz

      tar -xzf files/bin/etcd-${var.etcd_version}-linux-amd64.tar.gz -C files/bin --strip-components=1
      chmod +x files/bin/etcd files/bin/etcdctl
      rm files/bin/etcd-${var.etcd_version}-linux-amd64.tar.gz
    EOT
  }
}

resource "null_resource" "download_cni_binaries" {
  triggers = {
    cni_plugins_version = var.cni_plugins_version
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Download CNI plugins
      curl -L "https://github.com/containernetworking/plugins/releases/download/${var.cni_plugins_version}/cni-plugins-linux-amd64-${var.cni_plugins_version}.tgz" \
        -o files/cni-plugins.tgz
    EOT
  }
}

resource "null_resource" "nginx_reverse_proxy" {
  triggers = {
    cluster_ip = var.api_loadbalancer_host,

    nginx_reverse_proxy_file_hash = filesha256("${path.module}/templates/nginx-reverse-proxy.conf.tmpl")
  }

  connection {
    type        = "ssh"
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
    host        = var.api_loadbalancer_host
  }

  provisioner "remote-exec" {
    inline = [
      "sudo rm -rf ${var.remote_tmp_dir}",
      "mkdir -p ${var.remote_tmp_dir}",
      "sudo apt-get update -y",
      "sudo apt-get install -y nginx",
    ]
  }

  provisioner "file" {
    content = templatefile("${path.module}/templates/nginx-reverse-proxy.conf.tmpl", {
      apiserver_ips = values(var.controlplane_servers)
    })
    destination = "${var.remote_tmp_dir}/nginx.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /etc/nginx/conf.d/stream",
      "sudo cp ${var.remote_tmp_dir}/nginx.conf /etc/nginx/conf.d/stream/kube-apiserver-loadbalancer.conf",
      "if ! grep -q 'include.*stream' /etc/nginx/nginx.conf; then echo 'include /etc/nginx/conf.d/stream/*.conf;' | sudo tee -a /etc/nginx/nginx.conf; fi",
      "sudo systemctl restart nginx"
    ]
  }
}

resource "null_resource" "provision_control_plane" {
  for_each = toset(local.controlplane_hostnames)

  depends_on = [
    null_resource.download_k8s_binaries
  ]

  triggers = {
    etcd_cluster_state = var.etcd_cluster_state
    etcd_version       = var.etcd_version
    kubernetes_version = var.kubernetes_version

    ca_cert_hash                            = sha256(tls_self_signed_cert.ca_cert.cert_pem)
    etcd_server_cert_hash                   = sha256(tls_locally_signed_cert.etcd_server_cert.cert_pem)
    etcd_peer_cert_hash                     = sha256(tls_locally_signed_cert.etcd_peer_cert.cert_pem)
    etcd_healthcheck_client_cert_hash       = sha256(tls_locally_signed_cert.etcd_healthcheck_client_cert.cert_pem)
    kube_apiserver_cert_hash                = sha256(tls_locally_signed_cert.apiserver_cert.cert_pem)
    kube_apiserver_kubelet_client_cert_hash = sha256(tls_locally_signed_cert.apiserver_kubelet_client_cert.cert_pem)
    kube_apiserver_kubelet_client_key_hash  = sha256(tls_private_key.apiserver_kubelet_client_key.private_key_pem)
    kube_apiserver_etcd_client_cert_hash    = sha256(tls_locally_signed_cert.apiserver_etcd_client_cert.cert_pem)
    kube_apiserver_etcd_client_key_hash     = sha256(tls_private_key.apiserver_etcd_client_key.private_key_pem)
    sa_key_hash                             = sha256(tls_private_key.sa_key.private_key_pem)
    sa_pub_hash                             = sha256(tls_private_key.sa_key.public_key_pem)

    etcd_service_hash     = sha256(local.etcd_service)
    etcd_config_tmpl_hash = filesha256("${path.module}/templates/etcd-config.yaml.tmpl")

    kube_apiserver_service_hash = sha256(local.kube_apiserver_service)
    kube_apiserver_config_hash  = sha256(local.kube_apiserver_config)

    kube_controller_manager_service_hash    = sha256(local.kube_controller_manager_service)
    kube_controller_manager_kubeconfig_hash = sha256(local.kube_controller_manager_kubeconfig)

    kube_scheduler_service_hash    = sha256(local.kube_scheduler_service)
    kube_scheduler_kubeconfig_hash = sha256(local.kube_scheduler_kubeconfig)
  }

  connection {
    type        = "ssh"
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
    host        = var.controlplane_servers[each.key]
  }

  # Create remote tmp dir
  provisioner "remote-exec" {
    inline = [
      "sudo rm -rf ${var.remote_tmp_dir}",
      "sudo mkdir -p ${var.remote_tmp_dir}",
      "sudo chown -R ${var.ssh_user}:${var.ssh_user} ${var.remote_tmp_dir}"
    ]
  }

  # Upload binaries

  provisioner "remote-exec" {
    inline = [
      "mkdir -p ${var.remote_tmp_dir}/bin",
    ]
  }

  provisioner "file" {
    source      = "files/bin/kube-apiserver"
    destination = "${var.remote_tmp_dir}/bin/kube-apiserver"
  }

  provisioner "file" {
    source      = "files/bin/kube-controller-manager"
    destination = "${var.remote_tmp_dir}/bin/kube-controller-manager"
  }

  provisioner "file" {
    source      = "files/bin/kube-scheduler"
    destination = "${var.remote_tmp_dir}/bin/kube-scheduler"
  }

  provisioner "file" {
    source      = "files/bin/kubectl"
    destination = "${var.remote_tmp_dir}/bin/kubectl"
  }

  provisioner "file" {
    source      = "files/bin/etcd"
    destination = "${var.remote_tmp_dir}/bin/etcd"
  }

  provisioner "file" {
    source      = "files/bin/etcdctl"
    destination = "${var.remote_tmp_dir}/bin/etcdctl"
  }

  # Upload CA certs and keys

  provisioner "file" {
    source      = "${path.module}/certs/ca.crt"
    destination = "${var.remote_tmp_dir}/ca.crt"
  }

  provisioner "file" {
    source      = "${path.module}/certs/ca.key"
    destination = "${var.remote_tmp_dir}/ca.key"
  }

  # Upload etcd CA certs and keys

  provisioner "file" {
    source      = "${path.module}/certs/etcd/ca.crt"
    destination = "${var.remote_tmp_dir}/etcd-ca.crt"
  }

  provisioner "file" {
    source      = "${path.module}/certs/etcd/ca.key"
    destination = "${var.remote_tmp_dir}/etcd-ca.key"
  }

  # Upload etcd server cert

  provisioner "file" {
    source      = "${path.module}/certs/etcd/server.crt"
    destination = "${var.remote_tmp_dir}/etcd-server.crt"
  }

  provisioner "file" {
    source      = "${path.module}/certs/etcd/server.key"
    destination = "${var.remote_tmp_dir}/etcd-server.key"
  }

  # Upload etcd peer certs

  provisioner "file" {
    source      = "${path.module}/certs/etcd/peer.crt"
    destination = "${var.remote_tmp_dir}/etcd-peer.crt"
  }

  provisioner "file" {
    source      = "${path.module}/certs/etcd/peer.key"
    destination = "${var.remote_tmp_dir}/etcd-peer.key"
  }

  # Upload etcd healthcheck-client cert

  provisioner "file" {
    source      = "${path.module}/certs/etcd/healthcheck-client.crt"
    destination = "${var.remote_tmp_dir}/etcd-healthcheck-client.crt"
  }

  provisioner "file" {
    source      = "${path.module}/certs/etcd/healthcheck-client.key"
    destination = "${var.remote_tmp_dir}/etcd-healthcheck-client.key"
  }

  # Upload kube-apiserver certs

  provisioner "file" {
    source      = "${path.module}/certs/apiserver.crt"
    destination = "${var.remote_tmp_dir}/apiserver.crt"
  }

  provisioner "file" {
    source      = "${path.module}/certs/apiserver.key"
    destination = "${var.remote_tmp_dir}/apiserver.key"
  }

  provisioner "file" {
    source      = "${path.module}/certs/apiserver-kubelet-client.crt"
    destination = "${var.remote_tmp_dir}/apiserver-kubelet-client.crt"
  }

  provisioner "file" {
    source      = "${path.module}/certs/apiserver-kubelet-client.key"
    destination = "${var.remote_tmp_dir}/apiserver-kubelet-client.key"
  }

  # Upload apiserver-etcd-client cert

  provisioner "file" {
    source      = "${path.module}/certs/apiserver-etcd-client.crt"
    destination = "${var.remote_tmp_dir}/apiserver-etcd-client.crt"
  }

  provisioner "file" {
    source      = "${path.module}/certs/apiserver-etcd-client.key"
    destination = "${var.remote_tmp_dir}/apiserver-etcd-client.key"
  }

  # Upload SA keys
  provisioner "file" {
    source      = "${path.module}/certs/sa.key"
    destination = "${var.remote_tmp_dir}/sa.key"
  }

  provisioner "file" {
    source      = "${path.module}/certs/sa.pub"
    destination = "${var.remote_tmp_dir}/sa.pub"
  }

  # Upload config files

  provisioner "file" {
    content     = local.etcd_service
    destination = "${var.remote_tmp_dir}/etcd.service"
  }

  # each etcd peer needs its own config file
  provisioner "file" {
    content = templatefile("${path.module}/templates/etcd-config.yaml.tmpl", {
      initial_cluster = join(",", [
        for h in local.controlplane_hostnames : "${h}=https://${var.controlplane_servers[h]}:2380"
      ])
      peername                   = each.key
      cluster_name               = var.cluster_name
      advertise_client_url       = "https://${var.controlplane_servers[each.key]}:2379"
      listen_client_urls         = "https://${var.controlplane_servers[each.key]}:2379,https://127.0.0.1:2379"
      listen_peer_url            = "https://${var.controlplane_servers[each.key]}:2380"
      initial_advertise_peer_url = "https://${var.controlplane_servers[each.key]}:2380"
      cluster_state              = var.etcd_cluster_state
    })
    destination = "${var.remote_tmp_dir}/etcd-config.yaml"
  }

  provisioner "file" {
    content     = local.kube_apiserver_service
    destination = "${var.remote_tmp_dir}/kube-apiserver.service"
  }

  provisioner "file" {
    content     = local.kube_apiserver_config
    destination = "${var.remote_tmp_dir}/kube-apiserver-config.yaml"
  }

  provisioner "file" {
    content     = local.kube_controller_manager_service
    destination = "${var.remote_tmp_dir}/kube-controller-manager.service"
  }

  provisioner "file" {
    content     = local.kube_controller_manager_kubeconfig
    destination = "${var.remote_tmp_dir}/controller-manager.kubeconfig"
  }

  provisioner "file" {
    content     = local.kube_scheduler_service
    destination = "${var.remote_tmp_dir}/kube-scheduler.service"
  }

  provisioner "file" {
    content     = local.kube_scheduler_kubeconfig
    destination = "${var.remote_tmp_dir}/scheduler.kubeconfig"
  }

  # Apply configuration and start services

  provisioner "remote-exec" {
    inline = [
      # Stop services if exist
      "sudo systemctl stop etcd || true",
      "sudo systemctl stop kube-apiserver || true",
      "sudo systemctl stop kube-controller-manager || true",
      "sudo systemctl stop kube-scheduler || true",

      # Clean up old files if needed
      var.etcd_cluster_state == "new" ? "sudo rm -rf /var/lib/etcd" : "echo 'Skipping etcd data dir cleanup'",
      var.etcd_cluster_state == "new" ? "sudo rm -rf /etc/etcd" : "echo 'Skipping etcd config dir cleanup'",
      var.etcd_cluster_state == "new" ? "sudo rm -rf /etc/kubernetes" : "echo 'Skipping kubernetes config dir cleanup'",

      # Create dirs
      "sudo mkdir -p /etc/kubernetes/pki/etcd",

      # Copy CA certs/keys
      "sudo cp ${var.remote_tmp_dir}/ca.crt /etc/kubernetes/pki/ca.crt",
      "sudo cp ${var.remote_tmp_dir}/ca.key /etc/kubernetes/pki/ca.key",
      "sudo cp ${var.remote_tmp_dir}/etcd-ca.crt /etc/kubernetes/pki/etcd/ca.crt",
      "sudo cp ${var.remote_tmp_dir}/etcd-ca.key /etc/kubernetes/pki/etcd/ca.key",

      # Copy ETCD certs
      "sudo cp ${var.remote_tmp_dir}/etcd-server.crt /etc/kubernetes/pki/etcd/server.crt",
      "sudo cp ${var.remote_tmp_dir}/etcd-server.key /etc/kubernetes/pki/etcd/server.key",
      "sudo cp ${var.remote_tmp_dir}/etcd-peer.crt /etc/kubernetes/pki/etcd/peer.crt",
      "sudo cp ${var.remote_tmp_dir}/etcd-peer.key /etc/kubernetes/pki/etcd/peer.key",
      "sudo cp ${var.remote_tmp_dir}/etcd-healthcheck-client.crt /etc/kubernetes/pki/etcd/healthcheck-client.crt",
      "sudo cp ${var.remote_tmp_dir}/etcd-healthcheck-client.key /etc/kubernetes/pki/etcd/healthcheck-client.key",

      # Copy Apiserver certs
      "sudo cp ${var.remote_tmp_dir}/apiserver.crt /etc/kubernetes/pki/apiserver.crt",
      "sudo cp ${var.remote_tmp_dir}/apiserver.key /etc/kubernetes/pki/apiserver.key",
      "sudo cp ${var.remote_tmp_dir}/apiserver-kubelet-client.crt /etc/kubernetes/pki/apiserver-kubelet-client.crt",
      "sudo cp ${var.remote_tmp_dir}/apiserver-kubelet-client.key /etc/kubernetes/pki/apiserver-kubelet-client.key",
      "sudo cp ${var.remote_tmp_dir}/apiserver-etcd-client.crt /etc/kubernetes/pki/apiserver-etcd-client.crt",
      "sudo cp ${var.remote_tmp_dir}/apiserver-etcd-client.key /etc/kubernetes/pki/apiserver-etcd-client.key",

      # SA keys
      "sudo cp ${var.remote_tmp_dir}/sa.key /etc/kubernetes/pki/sa.key",
      "sudo cp ${var.remote_tmp_dir}/sa.pub /etc/kubernetes/pki/sa.pub",

      # Copy etcd config
      "sudo mkdir -p /etc/etcd/",
      "sudo cp ${var.remote_tmp_dir}/etcd.service /etc/systemd/system/etcd.service",
      "sudo cp ${var.remote_tmp_dir}/etcd-config.yaml /etc/etcd/etcd.yaml",

      # Copy kube apiserver manifests and services
      "sudo mkdir -p /etc/kubernetes/manifests",
      "sudo cp ${var.remote_tmp_dir}/kube-apiserver.service /etc/systemd/system/kube-apiserver.service",
      "sudo cp ${var.remote_tmp_dir}/kube-apiserver-config.yaml /etc/kubernetes/manifests/kube-apiserver.yaml",

      "sudo cp ${var.remote_tmp_dir}/kube-controller-manager.service /etc/systemd/system/kube-controller-manager.service",
      "sudo cp ${var.remote_tmp_dir}/controller-manager.kubeconfig /etc/kubernetes/controller-manager.kubeconfig",

      "sudo cp ${var.remote_tmp_dir}/kube-scheduler.service /etc/systemd/system/kube-scheduler.service",
      "sudo cp ${var.remote_tmp_dir}/scheduler.kubeconfig /etc/kubernetes/scheduler.kubeconfig",

      # Move binaries
      "sudo chmod +x ${var.remote_tmp_dir}/bin/*",
      "sudo cp ${var.remote_tmp_dir}/bin/* /usr/local/bin/",

      # Reload systemd and start services
      "sudo systemctl daemon-reload",
      "sudo systemctl enable etcd kube-apiserver kube-controller-manager kube-scheduler",

      # sleep for a random time to stagger the start of the control plane components
      "sleep $(( ( RANDOM % ${var.random_node_sleep} )  + 1 ))",
      "sudo systemctl start etcd kube-apiserver kube-controller-manager kube-scheduler",
    ]
  }

  # Clean up
  provisioner "remote-exec" {
    inline = [
      "sudo rm -rf ${var.remote_tmp_dir}",
      "sudo rm /tmp/terraform_*" # TODO: is there a better way to do this?
    ]
  }
}

# ===================================================================
# Kubelet Services
# ===================================================================

locals {
  kubelet_kubeconfig = templatefile("${path.module}/templates/kubelet.kubeconfig.tmpl", {
    ca_cert      = tls_self_signed_cert.ca_cert.cert_pem,
    server       = local.api_loadbalancer_url,
    cluster_name = var.cluster_name,
    client_cert  = tls_locally_signed_cert.apiserver_kubelet_client_cert.cert_pem,
    client_key   = tls_private_key.apiserver_kubelet_client_key.private_key_pem
  })

  kubelet_config = templatefile("${path.module}/templates/kubelet-config.yaml.tmpl", {
    cluster_dns_ip     = var.cluster_dns_ip,
    cluster_dns_domain = var.cluster_name,
  })
}

resource "null_resource" "provision_kubelets" {
  for_each = var.kubelet_servers

  depends_on = [
    null_resource.provision_control_plane, # ensures control plane is ready
  ]

  triggers = {
    kubernetes_version = var.kubernetes_version

    ca_cert_hash     = sha256(tls_self_signed_cert.ca_cert.cert_pem)
    server_cert_hash = sha256(tls_locally_signed_cert.kubelet_server_cert.cert_pem)
    server_key_hash  = sha256(tls_private_key.kubelet_server_key.private_key_pem)

    kubelet_service_tmpl_hash = filesha256("${path.module}/templates/kubelet.service.tmpl")
    kubelet_kubeconfig_hash   = sha256(local.kubelet_kubeconfig)
    kubelet_config_hash       = sha256(local.kubelet_config)
  }

  connection {
    type        = "ssh"
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
    host        = var.kubelet_servers[each.key]
  }

  # Create remote tmp dir
  provisioner "remote-exec" {
    inline = [
      "sudo rm -rf ${var.remote_tmp_dir}",
      "mkdir -p ${var.remote_tmp_dir}/bin",
      "sudo chown -R ${var.ssh_user}:${var.ssh_user} ${var.remote_tmp_dir}"
    ]
  }

  # Upload binaries

  provisioner "file" {
    source      = "files/bin/kubelet"
    destination = "${var.remote_tmp_dir}/bin/kubelet"
  }

  provisioner "file" {
    source      = "files/cni-plugins.tgz"
    destination = "${var.remote_tmp_dir}/cni-plugins.tgz"
  }

  # Upload CA certs and keys

  provisioner "file" {
    source      = "${path.module}/certs/ca.crt"
    destination = "${var.remote_tmp_dir}/ca.crt"
  }

  provisioner "file" {
    source      = "${path.module}/certs/kubelet.crt"
    destination = "${var.remote_tmp_dir}/kubelet.crt"
  }

  provisioner "file" {
    source      = "${path.module}/certs/kubelet.key"
    destination = "${var.remote_tmp_dir}/kubelet.key"
  }

  # Upload kubelet configs

  provisioner "file" {
    content     = local.kubelet_kubeconfig
    destination = "${var.remote_tmp_dir}/kubelet.kubeconfig"
  }

  provisioner "file" {
    content     = local.kubelet_config
    destination = "${var.remote_tmp_dir}/kubelet-config.yaml"
  }

  provisioner "file" {
    content = templatefile("${path.module}/templates/kubelet.service.tmpl", {
      hostname = each.key
    })
    destination = "${var.remote_tmp_dir}/kubelet.service"
  }

  provisioner "remote-exec" {
    inline = [
      # Stop services if exist
      "sudo systemctl stop containerd || true",
      "sudo systemctl stop kubelet || true",

      # Move binaries
      "sudo chmod +x ${var.remote_tmp_dir}/bin/*",
      "sudo cp ${var.remote_tmp_dir}/bin/* /usr/local/bin/",

      # Install containerd and CNI plugins
      "sudo apt-get update -y",
      "sudo apt-get install -y containerd",

      # Enable networking for Flannel/CNI
      "sudo modprobe br_netfilter",
      # Enable iptables bridge-nf-call-iptables and bridge-nf-call-ip6tables
      "sudo sysctl -w net.bridge.bridge-nf-call-iptables=1",
      "sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=1",
      # Make the above settings persistent
      "echo 'net.bridge.bridge-nf-call-iptables=1' | sudo tee -a /etc/sysctl.conf",
      "echo 'net.bridge.bridge-nf-call-ip6tables=1' | sudo tee -a /etc/sysctl.conf",
      # Load br_netfilter module at boot
      "echo 'br_netfilter' | sudo tee /etc/modules-load.d/br_netfilter.conf",

      "sudo mkdir -p /opt/cni/bin",
      "sudo tar -xzf ${var.remote_tmp_dir}/cni-plugins.tgz -C /opt/cni/bin",

      # Copy CA certs/keys
      "sudo mkdir -p /var/lib/kubelet/pki",
      "sudo mkdir -p /var/lib/kubernetes/pki",
      "sudo mkdir -p /etc/kubernetes",

      "sudo cp ${var.remote_tmp_dir}/ca.crt /var/lib/kubernetes/pki/client-ca.crt",
      "sudo cp ${var.remote_tmp_dir}/kubelet.crt /var/lib/kubelet/pki/",
      "sudo cp ${var.remote_tmp_dir}/kubelet.key /var/lib/kubelet/pki/",

      "sudo cp ${var.remote_tmp_dir}/kubelet.kubeconfig /etc/kubernetes/kubelet.kubeconfig",
      "sudo cp ${var.remote_tmp_dir}/kubelet-config.yaml /var/lib/kubelet/config.yaml",
      "sudo cp ${var.remote_tmp_dir}/kubelet.service /etc/systemd/system/kubelet.service",

      # Reload systemd and start services
      "sudo systemctl daemon-reload",
      "sudo systemctl enable containerd kubelet",
      "sudo systemctl start containerd kubelet",
    ]
  }

  # Clean up
  provisioner "remote-exec" {
    inline = [
      "sudo rm -rf ${var.remote_tmp_dir}",
      "sudo rm /tmp/terraform_*" # TODO: is there a better way to do this?
    ]
  }
}

# ===================================================================
# Kube Proxy
# Provision kube-proxy on all nodes using a daemon set
# ===================================================================

locals {
  kube_proxy_spec = templatefile("${path.module}/templates/kube-system/kube-proxy.yaml.tmpl", {
    kubernetes_version   = var.kubernetes_version
    cluster_pod_cidr     = var.cluster_pod_cidr
    cluster_service_cidr = var.cluster_service_cidr
    kubeconfig           = local_file.admin_kubeconfig.content
    cluster_dns_domain   = var.cluster_dns_domain
    cluster_dns_ip       = var.cluster_dns_ip
    coredns_version      = var.coredns_version
  })

  coredns_spec = templatefile("${path.module}/templates/kube-system/coredns.yaml.tmpl", {
    cluster_dns_domain  = var.cluster_dns_domain
    cluster_dns_ip      = var.cluster_dns_ip
    coredns_version     = var.coredns_version
    upstream_dns_server = var.upstream_dns_server
  })

  flannel_spec = templatefile("${path.module}/templates/kube-system/kube-flannel.yaml.tmpl", {
    cluster_pod_cidr             = var.cluster_pod_cidr
    cni_plugins_version          = var.cni_plugins_version
    flannel_cni_plugin_image_tag = var.flannel_cni_plugin_image_tag
    flannel_image_tag            = var.flannel_image_tag
  })
}

# Provision kube-system services: kube-proxy and coredns

resource "null_resource" "provision_kube_system_services" {
  triggers = {
    kube_proxy_spec_hash = sha256(local.kube_proxy_spec)
    coredns_spec_hash    = sha256(local.coredns_spec)
    flannel_spec_hash    = sha256(local.flannel_spec)
  }

  connection {
    type        = "ssh"
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
    host        = var.controlplane_servers[local.controlplane_hostnames[0]]
  }

  # create the tmp dir
  provisioner "remote-exec" {
    inline = [
      "sudo rm -rf ${var.remote_tmp_dir}",
      "mkdir -p ${var.remote_tmp_dir}",
      "sudo chown -R ${var.ssh_user}:${var.ssh_user} ${var.remote_tmp_dir}"
    ]
  }

  # Upload the kubeconfig for the deployment
  provisioner "file" {
    content     = local_file.admin_kubeconfig.content
    destination = "${var.remote_tmp_dir}/kube-proxy.kubeconfig"
  }

  provisioner "file" {
    content     = local.kube_proxy_spec
    destination = "${var.remote_tmp_dir}/kube-proxy-deployment.yaml"
  }

  provisioner "file" {
    content     = local.coredns_spec
    destination = "${var.remote_tmp_dir}/coredns-deployment.yaml"
  }

  provisioner "file" {
    content     = local.flannel_spec
    destination = "${var.remote_tmp_dir}/flannel-deployment.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "export KUBECONFIG=${var.remote_tmp_dir}/kube-proxy.kubeconfig",
      "kubectl apply -f ${var.remote_tmp_dir}/coredns-deployment.yaml",
      "kubectl apply -f ${var.remote_tmp_dir}/kube-proxy-deployment.yaml",
      "kubectl apply -f ${var.remote_tmp_dir}/flannel-deployment.yaml",
      "kubectl -n kube-system rollout restart deployment kube-proxy",
      "kubectl -n kube-system rollout restart deployment coredns",
      "kubectl -n kube-system rollout restart daemonset kube-flannel-ds",
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "sudo rm -rf ${var.remote_tmp_dir}",
      "sudo rm /tmp/terraform_*" # TODO: is there a better way to do this?
    ]
  }
}
