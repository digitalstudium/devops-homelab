1. Generate CA private key

```bash
openssl genrsa -out ca.key 4096
```

2. Generate CA certificate (10 years, for example)

```bash
openssl req -x509 -new -nodes \
  -key ca.key \
  -days 3650 \
  -out ca.crt \
  -subj "/CN=My Homelab CA" \
  -addext "basicConstraints=critical,CA:TRUE"
```

3. Issue Gitlab certificate

```bash
# Generate CSR
openssl req -new -newkey rsa:4096 -nodes \
  -keyout gitlab.homelab.internal.key \
  -out gitlab.homelab.internal.csr \
  -subj "/CN=gitlab.homelab.internal" \
  -addext "subjectAltName = DNS:gitlab.homelab.internal"

# Generate certificate
openssl x509 -req -in gitlab.homelab.internal.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out gitlab.homelab.internal.crt \
  -days 3650 \
  -extfile <(printf "subjectAltName=DNS:gitlab.homelab.internal")

# set permissions
chmod 644 gitlab.homelab.internal.crt
chmod 600 gitlab.homelab.internal.key
```

4. Issue Gitlab registry certificate

```bash
# Generate CSR
openssl req -new -newkey rsa:4096 -nodes \
  -keyout registry.gitlab.homelab.internal.key \
  -out registry.gitlab.homelab.internal.csr \
  -subj "/CN=registry.gitlab.homelab.internal" \
  -addext "subjectAltName = DNS:registry.gitlab.homelab.internal"

# Generate certificate
openssl x509 -req -in registry.gitlab.homelab.internal.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out registry.gitlab.homelab.internal.crt \
  -days 3650 \
  -extfile <(printf "subjectAltName=DNS:registry.gitlab.homelab.internal")

# set permissions
chmod 644 registry.gitlab.homelab.internal.crt
chmod 600 registry.gitlab.homelab.internal.key
```

5. Create Kubernetes secrets

```bash
export KUBECONFIG=~/.kube/vmkube
kubectl config use-context admin@vmkube-1
kubectl create ns cert-manager
kubectl -n cert-manager create secret tls root-secret --cert=ca.crt --key=ca.key
kubectl create ns victoria-metrics-k8s-stack
kubectl -n victoria-metrics-k8s-stack create secret generic root-secret-cacert --from-file=cacert=ca.crt
kubectl config use-context admin@vmkube-2
kubectl create ns cert-manager
kubectl -n cert-manager create secret tls root-secret --cert=ca.crt --key=ca.key
kubectl create ns victoria-metrics-k8s-stack
kubectl -n victoria-metrics-k8s-stack create secret generic root-secret-cacert --from-file=cacert=ca.crt
```

5. Import `ca.crt` to local system:

```bash
sudo cp ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

And import to browser.

Step completed!
