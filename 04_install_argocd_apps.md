Run:

```bash
kubectl apply -f yamls/vmkube-1/root-app.yaml
```

You can observe status in ArgoCD UI.

After sync completed, add these lines to your `/etc/hosts` file:

```bash
192.168.193.1 argocd.vmkube-1.example.com
```
