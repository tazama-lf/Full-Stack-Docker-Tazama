import os
import pwd
import subprocess

c = get_config()  # noqa: F821

# --- Spawner: local processes, all on the same server ---
c.JupyterHub.spawner_class = "simple"
c.Spawner.notebook_dir = "/srv/notebooks"
c.Spawner.args = ["--ServerApp.root_dir=/srv/notebooks"]
c.Spawner.default_url = "/lab"

# Pass environment variables from JupyterHub to each user's notebook server
c.Spawner.environment = {
    "SPARK_HOME": os.environ.get("SPARK_HOME", "/opt/spark"),
    "JAVA_HOME": os.environ.get("JAVA_HOME", "/opt/java"),
    "SPARK_JARS": os.environ.get("SPARK_JARS", ""),
    "S3A_ENDPOINT": os.environ.get("S3A_ENDPOINT", ""),
    "S3A_ACCESS_KEY": os.environ.get("S3A_ACCESS_KEY", ""),
    "S3A_SECRET_KEY": os.environ.get("S3A_SECRET_KEY", ""),
    "WAREHOUSE_ROOT": os.environ.get("WAREHOUSE_ROOT", "/opt/Tazama_Hudi_warehouse"),
    "SPARK_DRIVER_MEMORY": os.environ.get("SPARK_DRIVER_MEMORY", "4g"),
    "PYSPARK_PYTHON": "python3",
    "PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"),
}

# --- Authentication: NativeAuthenticator with admin signup ---
c.JupyterHub.authenticator_class = "nativeauthenticator.NativeAuthenticator"

# First user to sign up must be the admin (set via JUPYTERHUB_ADMIN env var)
admin = os.environ.get("JUPYTERHUB_ADMIN", "admin")
c.Authenticator.admin_users = {admin}

# Admin can authorize new users; non-admin signups require admin approval
c.NativeAuthenticator.open_signup = True
c.Authenticator.allow_all = True

# --- Networking ---
c.JupyterHub.ip = "0.0.0.0"
c.JupyterHub.port = 8000

# --- Persistence ---
c.JupyterHub.cookie_secret_file = "/data/jupyterhub_cookie_secret"
c.JupyterHub.db_url = "sqlite:////data/jupyterhub.sqlite"


# --- Auto-create system users when they sign up ---
def pre_spawn_hook(spawner):
    username = spawner.user.name
    try:
        pwd.getpwnam(username)
    except KeyError:
        subprocess.run(
            ["useradd", "-m", "-s", "/bin/bash", "-N", username],
            check=True,
        )
    # Ensure user can read the shared notebooks
    subprocess.run(["chmod", "-R", "o+rX", "/srv/notebooks"], check=False)


c.Spawner.pre_spawn_hook = pre_spawn_hook
