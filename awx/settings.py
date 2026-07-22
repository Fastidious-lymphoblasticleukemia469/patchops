import os

DATABASES = {
    "default": {
        "ENGINE": "awx.main.db.profiled_pg",
        "NAME": os.environ.get("DATABASE_NAME", "awx"),
        "USER": os.environ.get("DATABASE_USER", "awx"),
        "PASSWORD": os.environ.get("DATABASE_PASSWORD", "awxpass"),
        "HOST": os.environ.get("DATABASE_HOST", "postgres"),
        "PORT": int(os.environ.get("DATABASE_PORT", "5432")),
    }
}

BROKER_URL = "redis://{}:{}/0".format(
    os.environ.get("REDIS_HOST", "redis"),
    os.environ.get("REDIS_PORT", "6379"),
)

CHANNEL_LAYERS = {
    "default": {
        "BACKEND": "channels_redis.core.RedisChannelLayer",
        "CONFIG": {
            "hosts": [BROKER_URL],
            "capacity": 10000,
            "group_expiry": 157784760,
        },
    }
}

SECRET_KEY = os.environ.get("SECRET_KEY", "awxsecretchangeme1234567890abcdef")

AWX_ADMIN_USER = os.environ.get("AWX_ADMIN_USER", "admin")
AWX_ADMIN_PASSWORD = os.environ.get("AWX_ADMIN_PASSWORD", "password")
AWX_ADMIN_EMAIL = os.environ.get("AWX_ADMIN_EMAIL", "admin@example.com")

ALLOWED_HOSTS = ["*"]

USE_X_FORWARDED_HOST = True
USE_X_FORWARDED_PORT = True

# Use docker for EE container isolation via the bind-mounted host socket.
# AWX 24.x hardcodes "podman" in jobs.py — the Dockerfile patches that to read
# this setting, so docker is actually used when set here.
PROCESS_ISOLATION_EXECUTABLE = 'docker'

# patchops' managed fleet (aptly + dev/staging/prod containers, see
# ../inventory.ini) is only reachable via localhost:<mapped-port> — exactly
# how a developer running ansible-playbook directly from this host reaches
# it. EE job containers get their own network namespace by default, which
# would make "localhost" resolve to the EE container itself. Running job
# containers with the host's network namespace makes them see the fleet
# exactly like a local ansible-playbook run does, with zero inventory
# changes. Linux-only; if this ever needs to run on macOS/Windows, switch
# patchops' inventory to the containers' docker-network hostnames instead.
#
# NOTE: this is also a DB-backed dynamic setting (awx.conf) — once a
# `Setting` row exists for this key, the DB value wins over this file. This
# assignment is only the fallback if that row is ever deleted; launch_web.sh
# sets the actual DB value on every boot.
DEFAULT_CONTAINER_RUN_OPTIONS = ['--network', 'host']

# awx-task reaches awxweb over plain HTTP inside Docker (no TLS on port 8052).
BROADCAST_WEBSOCKET_PORT = 8052
BROADCAST_WEBSOCKET_PROTOCOL = 'http'

# Write job private data to a host-accessible path so Docker daemon (via host socket)
# can mount it into EE containers. /tmp/awx-runner is a shared bind mount.
AWX_ISOLATION_BASE_PATH = '/tmp/awx-runner'
