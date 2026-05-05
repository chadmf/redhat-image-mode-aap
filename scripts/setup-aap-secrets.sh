#!/bin/bash
# Purpose: Initialize AAP Podman secrets with strong random passwords
# Usage: sudo ./scripts/setup-aap-secrets.sh [--regenerate]

set -euo pipefail

SECRETS_DIR="/var/lib/containers/storage/secrets"
BACKUP_DIR="/root/.aap-secrets-backup"
REGENERATE=false

# Parse arguments
if [[ "${1:-}" == "--regenerate" ]]; then
    REGENERATE=true
fi

# Generate strong password (32 chars, alphanumeric + special)
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Create secret safely
create_secret() {
    local name=$1
    local description=$2

    if podman secret inspect "$name" &>/dev/null; then
        if $REGENERATE; then
            echo "⚠️  Removing existing secret: $name"
            podman secret rm "$name"
        else
            echo "✓ Secret already exists: $name (use --regenerate to recreate)"
            return 0
        fi
    fi

    local password=$(generate_password)
    echo "$password" | podman secret create "$name" -

    # Backup password to secure location
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
    echo "$password" > "$BACKUP_DIR/$name.txt"
    chmod 600 "$BACKUP_DIR/$name.txt"

    echo "✓ Created secret: $name"
    echo "  Backup saved: $BACKUP_DIR/$name.txt"
}

# Check for root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root (system mode)"
   exit 1
fi

echo "=== AAP Podman Secrets Setup ==="
echo ""

# Create secrets
create_secret "aap-db-password" "PostgreSQL application user password"
create_secret "aap-db-admin-password" "PostgreSQL admin user password"

echo ""
echo "=== Setup Complete ==="
echo "✓ Secrets created in: $SECRETS_DIR"
echo "✓ Backups saved to: $BACKUP_DIR"
echo ""
echo "⚠️  IMPORTANT SECURITY NOTES:"
echo "  1. Backup passwords are stored in $BACKUP_DIR/*.txt"
echo "  2. These backups are for disaster recovery only"
echo "  3. Access requires root privileges"
echo "  4. Consider additional backup to secure vault/KMS"
echo ""
echo "Next steps:"
echo "  1. Verify secrets: podman secret ls"
echo "  2. Deploy quadlet files with Secret= directives"
echo "  3. Start services: systemctl daemon-reload && systemctl start aap-*.service"
