# ArgoCD Installation and Setup Guide

## Prerequisites

### 1. Install Required Tools

Install the `kubectl`, `helm`, and `argocd` CLI tools.
This can be done, for example, using [`arkade`](https://github.com/alexellis/arkade)

```bash
arkade get kubectl helm argocd
```

## Step 1: Adding the ArgoCD Helm Repository

```bash
# Add the official ArgoCD repository
helm repo add argo https://argoproj.github.io/argo-helm

# Update repository information
helm repo update
```

## Step 2: Installing ArgoCD

```bash
export KUBECONFIG=~/.kube/vmkube
kubectl config use-context admin@vmkube-1
helm upgrade --install argo argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set global.domain=argocd.vmkube-1.example.com \
  --set configs.params.server.insecure=true \
  --set server.ingress.enabled=true \
  --set server.ingress.ingressClassName=traefik \
  --set server.ingress.tls=true \
  --set server.ingress.annotations.cert-manager\.io/cluster-issuer=my-ca-issuer \
  --wait
```

**Parameter Explanation:**

- `global.domain=argocd.vmkube-1.example.com` - Domain for accessing ArgoCD (will be accessible after ingress installation)
- `configs.params.server.insecure=true` - Allow insecure connections (SSL will be terminated at the Ingress level)
- `server.ingress.enabled=true` - Enable Ingress
- `server.ingress.ingressClassName=traefik` - Use the Traefik Ingress Controller
- `server.ingress.tls=true` - Enable Ingress TLS
- `server.ingress.annotations.cert-manager\.io/cluster-issuer=my-ca-issuer` - Annotation for automatic certificate issuance using cert-manager

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
argocd login --port-forward \
  --port-forward-namespace argocd \
  --insecure \
  --username admin \
  --password $ARGOCD_PASSWORD \
  --insecure
```

## Step 5: Adding Clusters to ArgoCD

```bash
for cluster in vmkube-1 vmkube-2; do
  argocd cluster add -y --port-forward \
    --port-forward-namespace argocd \
    admin@$cluster \
    --name $cluster \
    --label cluster-name=$cluster \
    --upsert \
    --insecure
done
```

# Step 6: Accessing the ArgoCD Web UI via Port Forwarding

This step establishes a secure tunnel to access the ArgoCD web interface through port forwarding.

```bash
# Port forwarding to access the ArgoCD web UI
kubectl -n argocd port-forward deployments/argo-argocd-server 8080:8080
```

**After running this command:**

1. Open your web browser
2. Navigate to: `http://127.0.0.1:8080`
3. Log in using:
   - **Username:** `admin`
   - **Password:** The password you retrieved in Step 3

**Note:** Keep this terminal session running while you need access to the UI. The connection will terminate if you close the terminal or press `Ctrl+C`.
