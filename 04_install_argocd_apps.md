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
