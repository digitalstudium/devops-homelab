## Description

## Components

This homelab includes the following components:

- **GitLab** – separate VM

Two Kubernetes clusters on Talos Linux VMs with:
- **Local Path Provisioner** – storage
- **MetalLB** – ip addresses for load balancers
- **Traefik Ingress Controller** – ingress 
- **Istio** – service mesh
- **GitLab Runner** – executes GitLab CI jobs
- **ArgoCD** – GitOps continuous delivery
- **Kargo** – GitOps continuous promotion
- **Cert-manager** – automated TLS certificate issuing for ingress
- **External DNS** – automated DNS records creation for ingress
- **OpenBao** – secrets storage (fork of Vault)
- **External Secrets Operator** – syncs secrets from OpenBao to Kubernetes
- **VictoriaMetrics** – metrics storage and monitoring
- **Grafana** – metrics visualization and dashboards
- **Zalando Postgres Operator** – PostgreSQL database management on Kubernetes

## System Requirements:

This was tested on Debian 13 laptop with 16 cores, 32 GB RAM, and 200 GB disk space.

## Installation

Follow instructions in these files:

[**01_install_k8s.md**](https://github.com/digitalstudium/devops-homelab/blob/main/01_install_k8s.md)

[**02_create_ca_and_cert.md**](https://github.com/digitalstudium/devops-homelab/blob/main/02_create_ca_and_cert.md)

[**03_install_gitlab.md**](https://github.com/digitalstudium/devops-homelab/blob/main/03_install_gitlab.md)

[**04_install_argocd.md**](https://github.com/digitalstudium/devops-homelab/blob/main/04_install_argocd.md)

[**05_install_argocd_apps.md**](https://github.com/digitalstudium/devops-homelab/blob/main/05_install_argocd_apps.md)

[**06_connect_eso_to_openbao.md**](https://github.com/digitalstudium/devops-homelab/blob/main/06_connect_eso_to_openbao.md)

[**07_install_kargo_apps.md**](https://github.com/digitalstudium/devops-homelab/blob/main/07_install_kargo_apps.md)
