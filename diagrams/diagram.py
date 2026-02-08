class Operator:
    def __init__(self, name) -> None:
        self.name = name
        self.apps = []

    def append(self, app):
        self.apps.append(app)

    def display(self, prefix=""):
        print(f"{prefix}+-- Operator: {self.name}")
        for i, app in enumerate(self.apps):
            new_prefix = prefix + ("|   " if i < len(self.apps) - 1 else "    ")
            app.display(new_prefix)


class App:
    def __init__(self, name, operator) -> None:
        self.name = name
        self.operator = operator
        self.apps = []

    def append(self, app):
        self.apps.append(app)

    def display(self, prefix=""):
        operator_name = (
            self.operator.name if hasattr(self.operator, "name") else str(self.operator)
        )
        print(f"{prefix}+-- {self.name} (Operator: {operator_name})")
        for i, app in enumerate(self.apps):
            new_prefix = prefix + ("|   " if i < len(self.apps) - 1 else "    ")
            app.display(new_prefix)


# Build and display
kubernetes = Operator("vanilla")
argocd = App("ArgoCD", kubernetes)
postgres_operator = App("Postgres Operator", argocd)
gitlab_postgres_cluster = App("Gitlab Postgres Cluster", postgres_operator)
gitlab = App("Gitlab", argocd)

gitlab_postgres_cluster.append(gitlab)
postgres_operator.append(gitlab_postgres_cluster)
argocd.append(postgres_operator)
kubernetes.append(argocd)

kubernetes.display()
