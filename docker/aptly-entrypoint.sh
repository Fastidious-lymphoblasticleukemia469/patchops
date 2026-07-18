#!/usr/bin/env bash
set -Eeuo pipefail

APTLY_DATA="/var/cache/aptly"
APTLY_CONFIG="/etc/aptly/aptly.conf"
HOME_DIR="/home/aptly"
MARKER="$HOME_DIR/.initialized"
GNUPG_DIR="$HOME_DIR/.gnupg"
GPG_KEY_NAME="PatchOps Aptly"

# Create aptly user (uid 115 matching production)
id -u aptly >/dev/null 2>&1 || {
    groupadd -g 115 aptly
    useradd -u 115 -g aptly -s /bin/bash -d "$HOME_DIR" -m aptly
    echo "aptly:aptly" | chpasswd
    usermod -aG sudo aptly
    echo "aptly ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/aptly
}

# Ensure aptly owns the data directory
mkdir -p "$APTLY_DATA"/{db,pool,public,state}
chown -R aptly:aptly "$APTLY_DATA"

# First-run setup
if [ ! -f "$MARKER" ]; then
    echo "=== Aptly first-run setup ==="

    # Setup SSH
    mkdir -p "$HOME_DIR/.ssh"
    if [ -f /tmp/ssh_key.pub ]; then
        cp /tmp/ssh_key.pub "$HOME_DIR/.ssh/authorized_keys"
        chmod 600 "$HOME_DIR/.ssh/authorized_keys"
    fi
    chown -R aptly:aptly "$HOME_DIR/.ssh"

    # Create aptly config (production pattern)
    cat > "$APTLY_CONFIG" <<EOF
{
  "rootDir": "$APTLY_DATA",
  "dbDir": "$APTLY_DATA/db",
  "poolDir": "$APTLY_DATA/pool",
  "publicDir": "$APTLY_DATA/public",
  "architectures": ["amd64"],
  "downloadSpeed": 0,
  "downloadTimeout": "300s",
  "downloadRetries": 3,
  "parallelFlushWorkers": 2,
  "apiServer": { "enable": true, "listen": ":8080" }
}
EOF
    chown aptly:aptly "$APTLY_CONFIG"

    # Initialize aptly database
    echo "Initializing aptly database..."
    sudo -u aptly aptly -config="$APTLY_CONFIG" db recover

    # Import Ubuntu archive GPG keys to aptly user keyring
    echo "Importing Ubuntu archive GPG keys..."
    mkdir -p "$GNUPG_DIR"
    if [ -f /usr/share/keyrings/ubuntu-archive-keyring.gpg ]; then
        gpg --no-default-keyring --keyring /usr/share/keyrings/ubuntu-archive-keyring.gpg --export | \
        gpg --no-default-keyring --keyring "$GNUPG_DIR/trustedkeys.gpg" --import 2>/dev/null || true
    fi

    # Import third-party signing keys for repo verification
    echo "Importing third-party signing keys (Docker, NodeSource, Nginx)..."
    gpg --no-default-keyring --keyring "$GNUPG_DIR/trustedkeys.gpg" \
        --keyserver keyserver.ubuntu.com --recv-keys \
        2FD21310B49F6B46 \
        7EA0A9C3F273FCD8 \
        6F71F525282841EEDAF851B42F59B5F99B1BE0B4 \
        2>/dev/null || true

    # Fix GPG directory permissions (suppress "unsafe permissions" warning)
    chmod 700 "$GNUPG_DIR"

    # Export all keys to system keyring so gpgv (used by aptly mirror update) can find them
    echo "Exporting GPG keys to system keyring for gpgv verification..."
    mkdir -p /etc/apt/trusted.gpg.d
    gpg --no-default-keyring --keyring "$GNUPG_DIR/trustedkeys.gpg" --export | \
        gpg --dearmor | tee /etc/apt/trusted.gpg.d/patchops-keys.gpg > /dev/null

    chown -R aptly:aptly "$GNUPG_DIR/"

    # Generate PatchOps signing GPG key (non-interactive, 4096-bit RSA)
    echo "Generating PatchOps signing GPG key..."
    sudo -u aptly gpg --batch --gen-key --homedir "$GNUPG_DIR" <<GPG_KEY
Key-Type: RSA
Key-Length: 4096
Name-Real: $GPG_KEY_NAME
Name-Email: aptly@patchops.internal
Expire-Date: 0
%no-protection
%commit
GPG_KEY

    # Export public key for clients to download
    sudo -u aptly gpg --homedir "$GNUPG_DIR" --armor --export "$GPG_KEY_NAME" \
        > "$APTLY_DATA/public/patchops-aptly.gpg"
    chown aptly:aptly "$APTLY_DATA/public/patchops-aptly.gpg"
    echo "Public key exported to /var/cache/aptly/public/patchops-aptly.gpg"

    # Configure nginx to serve aptly repos
    # Serves environment-prefixed repos: /dev/, /staging/, /prod/
    cat > /etc/nginx/sites-available/aptly <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/cache/aptly/public;

    # Environment routes
    location /dev/ {
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    }

    location /staging/ {
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    }

    location /prod/ {
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    }

    # GPG public key for clients
    location /patchops-aptly.gpg {
        autoindex off;
        add_header Content-Type "application/octet-stream";
    }

    # Root for diagnostics
    location / {
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    }
}
NGINX
    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/aptly /etc/nginx/sites-enabled/aptly

    touch "$MARKER"
    chown aptly:aptly "$MARKER"

    echo "=== Aptly setup complete ==="
fi

# Ensure correct permissions (covers volume mounts and restarts)
chown -R aptly:aptly "$APTLY_DATA"
chown -R aptly:aptly "$GNUPG_DIR/"

# Start nginx
echo "Starting nginx..."
nginx

# Start SSH
echo "Starting SSH..."
exec /usr/sbin/sshd -D
