# ArgoCD Installation and Setup Guide

## Prerequisites

Install the `kubectl`, `helm`, and `argocd` CLI tools.
This can be done, for example, using [`arkade`](https://github.com/alexellis/arkade)

```bash
arkade get kubectl helm argocd
```

## Step 1: Adding the ArgoCD Helm Repository

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

## Step 2: Installing ArgoCD

```bash
export KUBECONFIG=~/.kube/vmkube
kubectl config use-context admin@vmkube-1
helm upgrade --install argo argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values values/vmkube-1/argocd.yaml \
  --wait
```

**Parameter Explanation:**

- `global.domain=argocd.vmkube-1.homelab.internal` – Domain for accessing ArgoCD (will be accessible after ingress installation).
- `configs.params.server.insecure=true` – Allow insecure connections inside the cluster (SSL termination is handled at the Ingress level).
- `configs.params.hydrator.enabled=true` – Enable Source Hydrator (Manifest Hydrator) functionality, allowing dynamic manifest generation and Git writes.
- `commitServer.enabled=true` – Enable the commit server component, required for writing generated manifests back to Git when using Source Hydrator.
- `server.ingress.enabled=true` – Enable Ingress.
- `server.ingress.ingressClassName=traefik` – Use the Traefik Ingress Controller.
- `server.ingress.tls=true` – Enable Ingress TLS.
- `server.ingress.annotations.cert-manager\.io/cluster-issuer=my-ca-issuer` – Annotation for automatic certificate issuance using cert-manager.

**Note:** Pay attention to the escaped dot in `cert-manager\.io`. This is necessary because a dot has special meaning in Helm parameters.

## Step 3: Retrieving the Admin Password

```bash
# Get the initial password from the secret
export ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)
echo $ARGOCD_PASSWORD
# Record the password in a secure location
```

**Important:** The initial password is only available for 24 hours after installation.

## Step 4: Configuring Access to ArgoCD

```bash
# Login via CLI
argocd login \
  --port-forward \
  --port-forward-namespace argocd \
  --plaintext \
  --username admin \
  --password $ARGOCD_PASSWORD
```

## Step 5: Adding Clusters to ArgoCD

```bash
for cluster in vmkube-1 vmkube-2; do
  argocd cluster add -y --port-forward \
    --port-forward-namespace argocd \
    --plaintext \
    admin@$cluster \
    --name $cluster \
    --label cluster-name=$cluster
done
```

## Step 6: Configuring GitLab Integration

Create `devops` group in GitLab and add token named `argocd` with `Reporter` role and `read_api` + `read_repository` permissions (pay attention to Expiration date!)

Then add credentials for this group to argocd:

```bash
export GITLAB_TOKEN=token
argocd repocreds add \
  --port-forward \
  --port-forward-namespace argocd \
  --plaintext \
  https://gitlab.homelab.internal/devops \
  --username token \
  --password $GITLAB_TOKEN
```

## Step 7: Add CA certificate to trusted

```bash
argocd cert add-tls \
  --port-forward \
  --port-forward-namespace argocd \
  --plaintext \
  gitlab.homelab.internal \
  --from ./ca.crt
```

## Step 8: Accessing the ArgoCD Web UI via Port Forwarding

This step establishes a secure tunnel to access the ArgoCD web interface through port forwarding.

```bash
# Port forwarding to access the ArgoCD web UI
kubectl -n argocd port-forward deployments/argo-argocd-server 8080:8080
```

**After running this command:**

1. Open your web browser
2. Navigate to: `http://127.0.0.1:8080` (http, not https, it's important)
3. Log in using:
   - **Username:** `admin`
   - **Password:** The password you retrieved in Step 3

Step completed!

**Note:** Keep this terminal session running while you need access to the UI. The connection will terminate if you close the terminal or press `Ctrl+C`.
