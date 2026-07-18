#!/usr/bin/env bash
set -Eeuo pipefail

# Minimal entrypoint: create user + SSH access so Ansible can connect.
# All configuration is handled by `ansible-playbook playbooks/setup-aptly.yml`.

APTLY_HOME="/home/aptly"

# Create aptly user (uid 115 matching production)
if ! id -u aptly >/dev/null 2>&1; then
    groupadd -g 115 aptly
    useradd -u 115 -g aptly -s /bin/bash -d "$APTLY_HOME" -m aptly
    echo "aptly:aptly" | chpasswd
    usermod -aG sudo aptly
    echo "aptly ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/aptly
fi

# Setup SSH key for Ansible access
mkdir -p "$APTLY_HOME/.ssh"
if [ -f /tmp/ssh_key.pub ]; then
    cp /tmp/ssh_key.pub "$APTLY_HOME/.ssh/authorized_keys"
    chmod 600 "$APTLY_HOME/.ssh/authorized_keys"
fi
chown -R aptly:aptly "$APTLY_HOME/.ssh"

echo "Starting SSH..."
exec /usr/sbin/sshd -D
