#!/usr/bin/env bash
# Standalone AWX Web Launcher
# Proper configuration for Docker Compose (non-K8s) deployment
#
# Key fixes applied:
# - Uses official entrypoint internally
# - Handles database migrations properly
# - Bootstrap AWX config if needed
#
# Scope: this script only bootstraps the objects AWX itself needs to exist
# before the API is reachable (admin user, org, credentials, EE, project).
# Job templates and schedules are NOT created here — see ../configure.yml,
# which is run separately (via `make configure` or manually) once the API is
# up, so the pipeline definition stays a reviewable, idempotent playbook
# instead of being buried in a shell heredoc.

set -e

# Fix for non-root users in container
if [ "$(id -u)" -ge 500 ]; then
    echo "awx:x:$(id -u):$(id -g):,,,:/var/lib/awx:/bin/bash" >> /tmp/passwd
    cat /tmp/passwd > /etc/passwd
    rm /tmp/passwd 2>/dev/null || true
fi

# Run database migrations (idempotent — skips already-applied ones)
awx-manage migrate --noinput

# Bootstrap AWX: admin user + remove demo data + core objects.
# Runs on every start — every operation is idempotent (get_or_create / update)
awx-manage shell << 'PYEOF'
import os
from django.contrib.auth.models import User
from awx.main.models import (
    Organization, Credential, CredentialType,
    Project, ExecutionEnvironment,
)
from awx.conf.models import Setting

PROJECT_PATH = '/var/lib/awx/projects/patchops'

# ---------------------------------------------------------------------------
# AWX defaults AWX_ISOLATION_SHOW_PATHS to Podman-specific :O (overlay) mounts,
# which Docker's CLI rejects outright ("invalid mode: O"). Clear it so no :O
# flags reach `docker run` — required since settings.py sets
# PROCESS_ISOLATION_EXECUTABLE=docker.
# ---------------------------------------------------------------------------
obj, _ = Setting.objects.update_or_create(key='AWX_ISOLATION_SHOW_PATHS', defaults={'value': []})
obj.value = []
obj.save()
print('[init] cleared AWX_ISOLATION_SHOW_PATHS (Docker does not support :O overlay mode)')

# ---------------------------------------------------------------------------
# DEFAULT_CONTAINER_RUN_OPTIONS is also a DB-backed dynamic setting, defaulting
# to Podman's '--network slirp4netns:...' — plain settings.py assignments are
# ignored once this key exists in the DB. patchops' managed fleet (aptly +
# dev/staging/prod containers) is only reachable via localhost:<mapped-port>,
# so EE job containers need the host's network namespace to reach them
# exactly like a developer running ansible-playbook directly from this host
# would. Linux-only.
# ---------------------------------------------------------------------------
obj, _ = Setting.objects.update_or_create(key='DEFAULT_CONTAINER_RUN_OPTIONS', defaults={'value': ['--network', 'host']})
obj.value = ['--network', 'host']
obj.save()
print('[init] set DEFAULT_CONTAINER_RUN_OPTIONS to --network host')

# ---------------------------------------------------------------------------
# Admin user
# ---------------------------------------------------------------------------
u = os.environ.get('AWX_ADMIN_USER',  'admin')
p = os.environ.get('AWX_ADMIN_PASSWORD', 'password')
e = os.environ.get('AWX_ADMIN_EMAIL', 'admin@example.com')

if not User.objects.filter(username=u).exists():
    User.objects.create_superuser(u, e, p)
    print(f'[init] admin user created: {u}')
else:
    admin_user = User.objects.get(username=u)
    admin_user.set_password(p)
    admin_user.save()
    print(f'[init] admin user password synced: {u}')

admin = User.objects.get(username=u)

# ---------------------------------------------------------------------------
# Remove AWX demo / default data injected by migrations
# ---------------------------------------------------------------------------
Project.objects.filter(name='Demo Project').delete()

try:
    org = Organization.objects.get(name='Default')
    if not (org.inventory_set.exists() or org.project_set.exists()
            or org.credential_set.exists()):
        org.delete()
        print('[init] removed Default organization')
except Organization.DoesNotExist:
    pass

# ---------------------------------------------------------------------------
# Organization
# ---------------------------------------------------------------------------
org, created = Organization.objects.get_or_create(name='PatchOps')
if created:
    print('[init] created organization: PatchOps')

# ---------------------------------------------------------------------------
# Credentials
# ---------------------------------------------------------------------------
ssh_key_path = '/var/lib/awx/patchops-ssh-key'
ssh_key = open(ssh_key_path).read() if os.path.exists(ssh_key_path) else ''

machine_type = CredentialType.objects.get(name='Machine')
vault_type   = CredentialType.objects.get(name='Vault')

# Machine (SSH key for the patchops fleet — aptly host + dev/staging/prod
# clients; inventory.ini overrides ansible_user=aptly for the aptly host, so
# this credential's username only applies to the ubuntu client group)
cred_ssh, _ = Credential.objects.get_or_create(
    name='patchops-machine-ssh', organization=org, credential_type=machine_type,
    defaults={'created_by': admin},
)
cred_ssh.inputs = {'username': 'ansible', 'ssh_key_data': ssh_key}
cred_ssh.save()
print('[init] credential ready: patchops-machine-ssh')

# Vault (ansible-vault password — must match group_vars/all/vault.yml's
# encryption password, i.e. the repo's .vault_pass file)
vault_pass = os.environ.get('AWX_VAULT_PASSWORD', '')
cred_vault, _ = Credential.objects.get_or_create(
    name='patchops-vault', organization=org, credential_type=vault_type,
    defaults={'created_by': admin},
)
cred_vault.inputs = {'vault_password': vault_pass}
cred_vault.save()
print('[init] credential ready: patchops-vault')

# ---------------------------------------------------------------------------
# Execution Environment (local image — pulled from host Docker via socket)
# ---------------------------------------------------------------------------
ee, created = ExecutionEnvironment.objects.get_or_create(
    name='patchops-ee',
    defaults={'image': 'docker.io/2ssk/patchops-ee:latest', 'pull': 'missing'},
)
ee.image = 'docker.io/2ssk/patchops-ee:latest'
ee.pull  = 'missing'
ee.save()
if created:
    print('[init] created execution environment: patchops-ee')
else:
    print('[init] execution environment ready: patchops-ee')

# ---------------------------------------------------------------------------
# Project (Manual — reads from the mounted local repo)
# ---------------------------------------------------------------------------
project, created = Project.objects.get_or_create(
    name='patchops', organization=org,
    defaults={
        'scm_type':   '',          # empty string = Manual project
        'local_path': 'patchops',  # relative to /var/lib/awx/projects/
        'created_by': admin,
    },
)
if created:
    print('[init] created project: patchops')
else:
    print('[init] project ready: patchops')
PYEOF

# Hand off to AWX's own official entrypoint (uwsgi/daphne/nginx)
exec /usr/bin/launch_awx_web.sh
