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

Place a script `/etc/NetworkManager/dispatcher.d/50-set-vmkube-dns` with content:

```bash
#!/bin/bash
if [ "$1" = "vmkube-br0" ] && [ "$2" = "up" ]; then
resolvectl dns "$1" <first dns ip> <second dns ip>
resolvectl domain "$1" "~homelab.internal"
fi
```

Make it executable and restart NetworkManager:

```bash
sudo chmod 755 /etc/NetworkManager/dispatcher.d/50-set-vmkube-dns
sudo systemctl restart NetworkManager
```

Check if DNS resolution works:

```bash
nslookup postgres.vmkube-1.homelab.internal
```

It should be resolved to ingress LoadBalancer IP.

7. Unseal OpenBao
   Use this [guide](https://openbao.org/docs/platform/k8s/helm/run/#cli-initialize-and-unseal)

```bash
kubectl -n openbao  exec -it vmkube-1-openbao-0 -- bao operator init
kubectl -n openbao  exec -it vmkube-1-openbao-0 -- bao operator unseal <Unseal Key 1>
kubectl -n openbao  exec -it vmkube-1-openbao-0 -- bao operator unseal <Unseal Key 2>
...
kubectl -n openbao  exec -it vmkube-1-openbao-0 -- bao operator unseal <Unseal Key 5>
```

8. Login to ArgoCD, Grafana, OpenBao etc.

```bash
# get grafana password
kubectl get secret -n victoria-metrics-k8s-stack vmkube-1-victoria-metrics-k8s-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

Step completed!
