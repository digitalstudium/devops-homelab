1. Create `argocd-apps` repository in `devops` group of GitLab.
2. Push `values` and `yamls` folders from this repo there.
3. Then run:

```bash
kubectl apply -f yamls/vmkube-1/root-app.yaml
```

You can observe status in ArgoCD UI.
