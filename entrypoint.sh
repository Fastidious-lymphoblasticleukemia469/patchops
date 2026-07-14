#!/usr/bin/env bash
set -Eeuo pipefail

USER="ansible"
MARKER="/home/$USER/.initialized"

# First-run setup
if [ ! -f "$MARKER" ]; then
    # Create user
    id -u "$USER" >/dev/null 2>&1 || {
        useradd -m -s /bin/bash "$USER"
        echo "$USER:$USER" | chpasswd
        usermod -aG sudo "$USER"
        echo "$USER ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USER
    }

    # Setup SSH
    mkdir -p /home/$USER/.ssh
    if [ -f /tmp/ssh_key.pub ]; then
        cp /tmp/ssh_key.pub /home/$USER/.ssh/authorized_keys
        chmod 600 /home/$USER/.ssh/authorized_keys
    fi
    chown -R $USER:$USER /home/$USER/.ssh

    # Enable password auth
    sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null || true

    touch "$MARKER"
    chown $USER:$USER "$MARKER"
fi

exec /usr/sbin/sshd -D
