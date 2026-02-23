1. Create `kargo-apps` repository in `devops` group of GitLab.
2. Clone the repository to your local machine.
3. Copy and push content of `kargo-apps` folder to gitlab `kargo-apps` repo.
4. Then run:

```bash
export KUBECONFIG=~/.kube/vmkube
kubectl config use-context admin@vmkube-1
kubectl apply -f kargo-apps/root-apps.yaml
```

Observe changes in Kargo UI.

Step completed!
