#!/usr/bin/env bash
# Standalone AWX Task Launcher
# Proper configuration for Docker Compose (non-K8s) deployment
#
# Key fixes applied:
# - Uses provision_instance with --node_type=hybrid for standalone mode
# - Handles receptor configuration properly

set -e

# Fix for non-root users in container
if [ "$(id -u)" -ge 500 ]; then
    echo "awx:x:$(id -u):$(id -g):,,,:/var/lib/awx:/bin/bash" >> /tmp/passwd
    cat /tmp/passwd > /etc/passwd
    rm /tmp/passwd 2>/dev/null || true
fi

# Ensure receptor directory exists
mkdir -p /var/run/receptor /etc/receptor

# Create default receptor config if it doesn't exist (needed for dispatcher)
if [ ! -f /etc/receptor/receptor.conf ]; then
    cat > /etc/receptor/receptor.conf << 'EOF'
---
- node:
    id: awx
- local-only:
    local: true
- control-service:
    service: control
    filename: /var/run/receptor/receptor.sock
- work-command:
    worktype: local
    command: /var/lib/awx/venv/awx/bin/ansible-runner
    params: worker
    allowruntimeparams: true
EOF
    echo "Created default receptor config"
fi

# Start receptor in the background before supervisord.
# Supervisord does NOT manage receptor; it must be running before the
# dispatcher starts or every job dispatch fails with "socket does not exist".
echo "[task] Starting receptor..."
receptor --config /etc/receptor/receptor.conf > /var/log/receptor.log 2>&1 &
RECEPTOR_PID=$!

echo "[task] Waiting for receptor socket..."
for i in $(seq 1 30); do
    [ -S /var/run/receptor/receptor.sock ] && echo "[task] Receptor socket ready" && break
    if ! kill -0 $RECEPTOR_PID 2>/dev/null; then
        echo "[task] Receptor died! Log:"; cat /var/log/receptor.log; exit 1
    fi
    sleep 1
done
[ -S /var/run/receptor/receptor.sock ] || { echo "[task] Receptor socket timeout"; exit 1; }

# Verify EE image is available in the host Docker daemon.
# AWX uses PROCESS_ISOLATION_EXECUTABLE=docker so EE containers are launched via
# docker run on the host socket — no Podman, no image transfer needed.
echo "[task] Verifying EE image is available in Docker..."
for img in 2ssk/patchops-ee:latest; do
    if docker image inspect "$img" >/dev/null 2>&1; then
        echo "[task] EE image ready: $img"
    else
        echo "[task] EE image not found: $img — pulling..."
        docker pull "$img" || echo "[task] Warning: pull failed — jobs using this EE will fail at launch"
    fi
done

# Wait for migrations
wait-for-migrations

# =============================================================================
# Key Fix: Patch ansible-runner to handle PROCESS_ISOLATION_EXECUTABLE=None
# When process isolation is disabled, ansible-runner tries to run [None, '--version']
# which fails. This patch adds a None check at the start of the function.
# =============================================================================
echo "[task] Patching ansible-runner to handle disabled process isolation..."
python3 -c "
import os
fpath = '/var/lib/awx/venv/awx/lib/python3.11/site-packages/ansible_runner/utils/__init__.py'
if os.path.exists(fpath):
    with open(fpath, 'r') as f:
        content = f.read()
    if 'if not isolation_executable:' not in content:
        content = content.replace(
            'def check_isolation_executable_installed(isolation_executable: str) -> bool:',
            'def check_isolation_executable_installed(isolation_executable: str) -> bool:\n    if not isolation_executable: return False'
        )
        with open(fpath, 'w') as f:
            f.write(content)
        print('Patched ansible-runner')
    else:
        print('ansible-runner already patched')
" || echo "[task] Warning: could not patch ansible-runner"

# =============================================================================
# Key Fix: Explicit hostname + node_type required for non-Kubernetes deployments
# The bare `provision_instance` command defaults to K8s mode and errors out
# =============================================================================
awx-manage provision_instance --hostname=awx --node_type=hybrid || true

# Create controlplane and default instance groups if missing.
# provision_instance registers the node but never creates these groups;
# the task scheduler crashes with NoneType on controlplane_ig without them.
awx-manage register_queue --queuename controlplane --hostnames awx || true
awx-manage register_queue --queuename default --hostnames awx || true

# Start supervisor (manages all AWX task services)
exec supervisord -c /etc/supervisord_task.conf
