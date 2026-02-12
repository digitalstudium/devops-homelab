1. Create `argocd-apps` repository in `devops` group of GitLab.
2. Add your public ssh key to the GitLab account.
3. Clone the repository to your local machine.
4. Copy and push `values` and `yamls` folders from github repo to gitlab `argocd-apps` repo.
5. Then run:

```bash
export KUBECONFIG=~/.kube/vmkube
kubectl config use-context admin@vmkube-1
kubectl apply -f yamls/vmkube-1/root-app.yaml
```

Observe sync in ArgoCD UI.

6. DNS settings.

Check `EXTERNAL-IP` of the coredns (external-dns) service:

```bash
kubectl config use-context admin@vmkube-1
kubectl get svc -n external-dns coredns
kubectl config use-context admin@vmkube-2
kubectl get svc -n external-dns coredns
```

Next steps depend on your environment.

For example you can add all DNS IPs to `/etc/resolv.conf` like this:

```bash
nameserver 192.168.193.2
nameserver 192.168.3.1
```

or like this:

```bash
sudo resolvectl dns vmkube-br0 192.168.194.2 192.168.193.2
sudo resolvectl domain vmkube-br0 "~homelab.internal"
```

Check if DNS resolution works:

```bash
nslookup postgres.vmkube-1.homelab.internal
```

It should be resolved to ingress LoadBalancer IP.

7. Unseal OpenBao
   Use this [guide](https://openbao.org/docs/platform/k8s/helm/run/#cli-initialize-and-unseal)

Step completed!
