## 1. Set up OpenBao (on vmkube-1)

### 1.1 Enable Kubernetes auth for each cluster

OpenBao will have separate auth mount points – one per cluster.

```bash
kubectl -n openbao exec -it vmkube-1-openbao-0 -- env VAULT_TOKEN=<root-token> bao auth enable -path=vmkube-1 kubernetes
kubectl -n openbao exec -it vmkube-1-openbao-0 -- env VAULT_TOKEN=<root-token> bao auth enable -path=vmkube-2 kubernetes
```

### 1.2 Configure auth for vmkube-1 (where OpenBao runs)

Since OpenBao is inside vmkube-1, it can use the in-cluster service account to talk to the Kubernetes API.

```bash
# Run this from a pod in vmkube-1 (or use a token with appropriate permissions)
kubectl -n openbao exec -it vmkube-1-openbao-0 -- \
    sh -c "export VAULT_TOKEN=<root-token>; \
    bao write auth/vmkube-1/config \
    kubernetes_host='https://kubernetes.default.svc.cluster.local' \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    token_reviewer_jwt=\"\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)\""
```

### 1.3 Configure auth for vmkube-2 (remote cluster)

For the remote cluster, you need to provide OpenBao with credentials to call its Kubernetes API (to validate JWTs).  
Service account is already created in vmkube-2 with permission to create `tokenreviews`.
Get a token for this service account, vmkube-2 api endpoint and ca cert:

```bash
kubectl config use-context admin@vmkube-2
export VMKUBE_2_OPENBAO_TOKEN=$(kubectl get secret openbao-auth-delegator-token -n external-secrets -o jsonpath='{.data.token}' | base64 -d)
export VMKUBE_2_API_ENDPOINT=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > vmkube-2-ca.crt
```

Then configure the auth method in OpenBao:

```bash
kubectl config use-context admin@vmkube-1
kubectl cp vmkube-2-ca.crt openbao/vmkube-1-openbao-0:/tmp/vmkube-2-ca.crt
kubectl -n openbao exec -it vmkube-1-openbao-0 -- env VAULT_TOKEN=<root-token> bao write auth/vmkube-2/config \
    kubernetes_host="$VMKUBE_2_API_ENDPOINT" \
    kubernetes_ca_cert=@/tmp/vmkube-2-ca.crt \
    token_reviewer_jwt="$VMKUBE_2_OPENBAO_TOKEN"
```

### 1.4 Create a policy and role for external-secrets

First, create a policy that grants read access to your secrets (e.g., at path `kv/data/*`):

```bash
kubectl -n openbao exec -it vmkube-1-openbao-0 -- env VAULT_TOKEN=<root-token> bao policy write eso-reader - <<EOF
path "kv/data/*" {
  capabilities = ["read"]
}
EOF
```

Then create a role for each cluster that binds the service account `external-secrets` (the default service account used by ESO) to the policy.

For vmkube-1:

```bash
kubectl -n openbao exec -it vmkube-1-openbao-0 -- env VAULT_TOKEN=<root-token> bao write auth/vmkube-1/role/eso-role \
    bound_service_account_names="vmkube-1-external-secrets" \
    bound_service_account_namespaces="*" \
    policies="eso-reader" \
    ttl="1h"
```

For vmkube-2:

```bash
kubectl -n openbao exec -it vmkube-1-openbao-0 -- env VAULT_TOKEN=<root-token> bao write auth/vmkube-2/role/eso-role \
    bound_service_account_names="vmkube-2-external-secrets" \
    bound_service_account_namespaces="*" \
    policies="eso-reader" \
    ttl="1h"
```

### 1.5 Enable a KV secrets engine (if not already)

```bash
kubectl -n openbao exec -it vmkube-1-openbao-0 -- env VAULT_TOKEN=<root-token> bao secrets enable -path=kv -version=2 kv
```

> **Note**: Be consistent with the version – external-secrets expects `v2` by default. If you use `v1`, you must set `version: v1` in the SecretStore.

---

## 2. Create an ExternalSecret to test

Push a test secret to OpenBao:

```bash
kubectl -n openbao exec -it vmkube-1-openbao-0 -- env VAULT_TOKEN=<root-token> bao kv put kv/mysecret password=123
```

```bash
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: test
spec:
  secretStoreRef:
    name: openbao-store
    kind: ClusterSecretStore
  target:
    name: test-secret
  data:
    - secretKey: password
      remoteRef:
        key: mysecret
        property: password
EOF
```

After applying the ExternalSecret, check that a Kubernetes secret `test-secret` is created.
