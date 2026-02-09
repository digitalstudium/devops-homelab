# Инструкция по установке и настройке ArgoCD

## Предварительные требования

### 1. Установите необходимые инструменты

Установите `kubectl`, `helm` и `argocd` CLI.
Это можно сделать, например, с помощью [`arkade`](https://github.com/alexellis/arkade)

```bash
arkade get kubectl helm argocd
```

## Шаг 1: Добавление Helm репозитория ArgoCD

```bash
# Добавьте официальный репозиторий ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm

# Обновите информацию о репозиториях
helm repo update
```

## Шаг 2: Установка ArgoCD

```bash
KUBECONFIG=~/.kube/vmkube
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

**Объяснение параметров:**

- `global.domain=argocd.vmkube-1.example.com` - домен для доступа к ArgoCD (будет доступе после установки ingress)
- `configs.params.server.insecure=true` - разрешение небезопасного подключения (ssl будет терминироваться на уровне Ingress)
- `server.ingress.enabled=true` - включение Ingress
- `server.ingress.ingressClassName=traefik` - использование Traefik Ingress Controller
- `server.ingress.tls=true` - включение Ingress TLS
- `server.ingress.annotations.cert-manager\.io/cluster-issuer=my-ca-issuer` - аннотация для автоматической выдачи сертификатов с помощью cert-manager

**Примечание:** Обратите внимание на экранирование точки в `cert-manager\.io`. Это необходимо, так как точка в параметрах Helm имеет специальное значение.

## Шаг 3: Получение пароля администратора

```bash
# Получите начальный пароль из секрета
export ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)
echo $ARGOCD_PASSWORD
echo
# Запишите пароль в безопасное место
```

**Важно:** Первый пароль будет доступен только в течение 24 часов после установки.

## Шаг 4: Настройка доступа к ArgoCD

```bash
# Логин через CLI
argocd login --port-forward \
  --port-forward-namespace argocd \
  --insecure \
  --username admin \
  --password $ARGOCD_PASSWORD \
  --insecure
```

## Шаг 5: Добавление кластеров в ArgoCD

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
