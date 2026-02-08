#!/usr/bin/env python3
"""ArgoCD установка и настройка."""

import base64
import os
from pathlib import Path

from homelab.utils import commands, config, logger

# Конфигурация
HELM_REPO_URL = "https://argoproj.github.io/argo-helm"
HELM_REPO_NAME = "argo"
ARGOCD_NAMESPACE = "argocd"
ARGOCD_CHART_NAME = "argo/argo-cd"
ARGOCD_RELEASE_NAME = "argo"
ARGOCD_VALUES_FILE = "/tmp/argocd-values.yaml"
ARGOCD_SERVER_DEPLOYMENT = "argo-argocd-server"
INITIAL_SECRET_NAME = "argocd-initial-admin-secret"
CONFIG = config.load()

# Значения для Helm
ARGOCD_VALUES = """global:
  domain: argocd.cluster-1.example.com

configs:
  params:
    server.insecure: "true"

server:
  ingress:
    enabled: true
    ingressClassName: traefik
    tls: true
    annotations:
      cert-manager.io/cluster-issuer: my-ca-issuer
"""


def create_argocd_values_file() -> None:
    """Создает файл значений для установки ArgoCD."""
    with open(ARGOCD_VALUES_FILE, "w") as f:
        f.write(ARGOCD_VALUES)
    logger.info(f"Файл значений создан: {ARGOCD_VALUES_FILE}")


def add_helm_repo() -> None:
    """Добавляет helm репозиторий ArgoCD."""
    logger.info("Добавляем Helm репозиторий ArgoCD...")
    command = ["helm", "repo", "add", HELM_REPO_NAME, HELM_REPO_URL]
    commands.run(command)


def install_argocd(base_dir: Path) -> None:
    """Устанавливает ArgoCD с помощью Helm."""
    logger.info("Устанавливаем ArgoCD...")

    kubeconfig_path = os.path.join(base_dir, "cluster-1", "kubeconfig")

    command = [
        "helm",
        "--kubeconfig",
        kubeconfig_path,
        "upgrade",
        "--install",
        "--create-namespace",
        ARGOCD_RELEASE_NAME,
        ARGOCD_CHART_NAME,
        "-n",
        ARGOCD_NAMESPACE,
        "-f",
        ARGOCD_VALUES_FILE,
        "--wait",
    ]

    commands.run(command)


def wait_for_argocd_server(base_dir: Path) -> None:
    """Ожидает готовности сервера ArgoCD."""
    logger.info("Ожидаем готовности сервера ArgoCD...")

    kubeconfig_path = os.path.join(base_dir, "cluster-1", "kubeconfig")
    env = os.environ.copy()
    env["KUBECONFIG"] = kubeconfig_path

    command = [
        "kubectl",
        "wait",
        "--for=condition=available",
        f"deployment/{ARGOCD_SERVER_DEPLOYMENT}",
        "-n",
        ARGOCD_NAMESPACE,
        "--timeout=300s",
    ]

    commands.run(command, env=env)


def get_initial_password(base_dir: Path) -> str:
    """Получает начальный пароль администратора."""
    logger.info("Получаем начальный пароль администратора...")

    kubeconfig_path = os.path.join(base_dir, "cluster-1", "kubeconfig")
    env = os.environ.copy()
    env["KUBECONFIG"] = kubeconfig_path

    # Получаем пароль из секрета
    command = [
        "kubectl",
        "-n",
        ARGOCD_NAMESPACE,
        "get",
        "secret",
        INITIAL_SECRET_NAME,
        "-o",
        "jsonpath={.data.password}",
    ]

    result = commands.run(command, env=env)  # Получаем CompletedProcess
    encoded_password = result.stdout.strip()  # Извлекаем stdout

    if not encoded_password:
        logger.die("Ошибка: не удалось получить начальный пароль")

    # Декодируем base64

    try:
        decoded_password = base64.b64decode(encoded_password).decode("utf-8")
        return decoded_password
    except Exception as e:
        logger.die(f"Ошибка декодирования пароля: {e}")


def login_to_argocd(password: str, base_dir: Path) -> None:
    """Логинится в ArgoCD."""
    logger.info("Логинимся в ArgoCD...")

    command = [
        "argocd",
        "login",
        "--username",
        "admin",
        "--password",
        password,
        "--insecure",
        "--port-forward",
        "--plaintext",
        "--port-forward-namespace",
        "argocd",
    ]

    kubeconfig_path = os.path.join(base_dir, "cluster-1", "kubeconfig")
    env = os.environ.copy()
    env["KUBECONFIG"] = kubeconfig_path

    commands.run(command, env=env)


def add_cluster_to_argocd(cluster_name: str, base_dir: Path) -> None:
    """Добавляет кластер в ArgoCD."""
    logger.info(f"Добавляем {cluster_name}...")

    kubeconfig_path = os.path.join(base_dir, cluster_name, "kubeconfig")
    env = os.environ.copy()
    env["KUBECONFIG"] = (
        os.path.join(base_dir, "cluster-1", "kubeconfig") + ":" + kubeconfig_path
    )

    command = [
        "argocd",
        "cluster",
        "add",
        f"admin@{cluster_name}",
        "--insecure",
        "--port-forward",
        "--plaintext",
        "--port-forward-namespace",
        "argocd",
        "--yes",
    ]

    commands.run(command, env=env)


def list_argocd_clusters() -> None:
    """Выводит список кластеров в ArgoCD."""
    logger.info("Список кластеров в ArgoCD:")

    command = [
        "argocd",
        "cluster",
        "list",
        "--plaintext",
        "--port-forward-namespace",
        "argocd",
    ]
    commands.run(command)


def setup_kubeconfig_for_cluster1(base_dir: Path) -> None:
    """Устанавливает KUBECONFIG для cluster-1."""
    kubeconfig_path = os.path.join(base_dir, "cluster-1", "kubeconfig")
    os.environ["KUBECONFIG"] = kubeconfig_path
    print(f"KUBECONFIG установлен на: {kubeconfig_path}")


def display_final_instructions(password: str) -> None:
    """Выводит финальные инструкции."""
    print("\n" + "=" * 60)
    logger.ok("Готово! ArgoCD настроен с доступом через port-forward.")
    logger.info(
        "Используйте 'export ARGOCD_OPTS=\"--port-forward-namespace argocd\"' для последующих команд."
    )
    logger.info(f"Начальный пароль: {password}")
    print("=" * 60 + "\n")


def cleanup_temp_files() -> None:
    """Удаляет временные файлы."""
    if os.path.exists(ARGOCD_VALUES_FILE):
        os.remove(ARGOCD_VALUES_FILE)
        logger.ok(f"Временный файл удален: {ARGOCD_VALUES_FILE}")


def install() -> None:
    """Основная агрегирующая функция."""
    logger.info("Начинаем установку и настройку ArgoCD...")

    # Шаг 1: Проверяем BASE_DIR
    base_dir = Path(CONFIG.base_dir)
    logger.info(f"BASE_DIR: {base_dir}")

    # Шаг 2: Создаем файл значений
    create_argocd_values_file()

    # Шаг 3: Добавляем Helm репозиторий
    add_helm_repo()

    # Шаг 4: Устанавливаем ArgoCD
    install_argocd(base_dir)

    # Шаг 5: Настраиваем port-forward
    setup_kubeconfig_for_cluster1(base_dir)

    # Шаг 6: Ждем готовности сервера
    wait_for_argocd_server(base_dir)

    # Шаг 7: Получаем пароль
    password = get_initial_password(base_dir)

    # Шаг 8: Логинимся в ArgoCD
    login_to_argocd(password, base_dir)

    # Шаг 9: Добавляем кластеры
    add_cluster_to_argocd("cluster-1", base_dir)
    add_cluster_to_argocd("cluster-2", base_dir)

    # Шаг 10: Выводим список кластеров
    list_argocd_clusters()

    # Шаг 11: Выводим инструкции
    display_final_instructions(password)

    # Шаг 12: Очистка
    cleanup_temp_files()
