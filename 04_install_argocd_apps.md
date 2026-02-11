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

You can observe status in ArgoCD UI.

6. DNS settings.

Check `EXTERNAL-IP` of the coredns (external-dns) service:

```bash
kubectl config use-context admin@vmkube-1
kubectl get svc -n external-dns coredns
kubectl config use-context admin@vmkube-2
kubectl get svc -n external-dns coredns
```

and check current DNS IP address:

```bash
resolvectl status
```

Then add all DNS IPs to `/etc/systemd/resolved.conf` like this:

```toml
[Resolve]
DNS=192.168.193.2 192.168.194.2 192.168.3.1
```

and restart systemd-resolved service:

```bash
sudo systemctl restart systemd-resolved
```

or to `/etc/resolv.conf` like this:

```bash
nameserver 192.168.193.2
nameserver 192.168.3.1
```

Check if DNS resolution works:

```bash
nslookup postgres.vmkube-1.homelab.internal
```

It should be resolved to ingress LoadBalancer IP.

7. CA certificates:

```bash
kubectl config use-context admin@vmkube-1
kubectl get secret root-secret -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 -d > vmkube-1-ca.crt
kubectl config use-context admin@vmkube-2
kubectl get secret root-secret -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 -d > vmkube-2-ca.crt
sudo cp {vmkube-1-ca.crt,vmkube-2-ca.crt} /usr/local/share/ca-certificates
sudo update-ca-certificates
```

And import them to browser.
