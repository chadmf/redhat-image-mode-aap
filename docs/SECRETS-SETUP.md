# AAP Podman Secrets Setup Guide

## Overview

This guide covers the setup and management of Podman secrets for the AAP image-mode deployment. Secrets replace hardcoded passwords in quadlet configuration files, providing a secure credential management solution.

## Automated Setup (Recommended)

### Prerequisites

- Root access (system mode secrets)
- Ansible installed with `community.general` collection
- Podman 4.0 or later

### Installation

```bash
# Install Ansible collections
ansible-galaxy collection install -r playbooks/requirements.yml

# Run Phase 1 security hardening playbook
sudo ansible-playbook playbooks/phase1-security-hardening.yml
```

The playbook will:
1. Generate strong random passwords (32 characters)
2. Create Podman secrets: `aap-db-password`, `aap-db-admin-password`
3. Backup passwords to `/root/.aap-secrets-backup/*.txt`
4. Update quadlet files to use secrets instead of hardcoded passwords
5. Implement network segmentation
6. Remove exposed database ports

### Verification

```bash
# List Podman secrets
sudo podman secret ls

# Expected output:
# ID          NAME                     DRIVER  CREATED        UPDATED
# ...         aap-db-password          file    X seconds ago  X seconds ago
# ...         aap-db-admin-password    file    X seconds ago  X seconds ago

# Verify secret backups exist
sudo ls -lh /root/.aap-secrets-backup/
# Expected: aap-db-password.txt, aap-db-admin-password.txt (mode 600)
```

## Manual Setup (Alternative)

If you prefer to create secrets manually or use custom passwords:

### Step 1: Generate Passwords

```bash
# Generate strong random passwords
DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
DB_ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

# Or use your own passwords
DB_PASSWORD="your-custom-password-here"
DB_ADMIN_PASSWORD="your-custom-admin-password-here"
```

### Step 2: Create Podman Secrets

```bash
# Create secrets (system mode - requires root)
echo "$DB_PASSWORD" | sudo podman secret create aap-db-password -
echo "$DB_ADMIN_PASSWORD" | sudo podman secret create aap-db-admin-password -
```

### Step 3: Backup Passwords Securely

```bash
# Create secure backup directory
sudo mkdir -p /root/.aap-secrets-backup
sudo chmod 700 /root/.aap-secrets-backup

# Save passwords
echo "$DB_PASSWORD" | sudo tee /root/.aap-secrets-backup/aap-db-password.txt
echo "$DB_ADMIN_PASSWORD" | sudo tee /root/.aap-secrets-backup/aap-db-admin-password.txt

# Secure permissions
sudo chmod 600 /root/.aap-secrets-backup/*.txt
```

### Step 4: Verify Secrets

```bash
# List secrets
sudo podman secret ls

# Inspect a secret (shows metadata only, not content)
sudo podman secret inspect aap-db-password
```

## Quadlet Integration

Secrets are referenced in quadlet files using the `Secret=` directive:

```ini
[Container]
# Old (insecure)
Environment=POSTGRESQL_PASSWORD=redhat

# New (secure)
Secret=aap-db-password,type=env,target=POSTGRESQL_PASSWORD
```

### Secret Directive Syntax

```
Secret=<secret-name>,type=<type>,target=<target>
```

- **secret-name**: Name of the Podman secret
- **type**: `env` (environment variable) or `mount` (file mount)
- **target**: Environment variable name or mount path

### Files Using Secrets

| Quadlet File | Secret | Environment Variable |
|--------------|--------|---------------------|
| aap-postgresql.container | aap-db-password | POSTGRESQL_PASSWORD |
| aap-postgresql.container | aap-db-admin-password | POSTGRESQL_ADMIN_PASSWORD |
| aap-controller.container | aap-db-password | DATABASE_PASSWORD |
| aap-hub.container | aap-db-password | DATABASE_PASSWORD |
| aap-eda-controller.container | aap-db-password | DATABASE_PASSWORD |

## Secret Rotation

### When to Rotate

- Regular schedule (every 90-180 days)
- After suspected compromise
- When team members with access leave
- Compliance requirements

### Rotation Procedure

```bash
# 1. Generate new password
NEW_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

# 2. Remove old secret
sudo podman secret rm aap-db-password

# 3. Create new secret
echo "$NEW_PASSWORD" | sudo podman secret create aap-db-password -

# 4. Update backup
echo "$NEW_PASSWORD" | sudo tee /root/.aap-secrets-backup/aap-db-password.txt
sudo chmod 600 /root/.aap-secrets-backup/aap-db-password.txt

# 5. Restart affected services
sudo systemctl restart aap-postgresql.service
sudo systemctl restart aap-controller.service
sudo systemctl restart aap-hub.service
sudo systemctl restart aap-eda-controller.service

# 6. Verify connectivity
sudo journalctl -u aap-controller.service -n 50 | grep -i database
```

## Troubleshooting

### Secret Not Found

```bash
# Symptom: Container fails to start with "secret not found"
# Check if secret exists
sudo podman secret ls | grep aap-db-password

# If missing, recreate using playbook or manual steps
sudo ansible-playbook playbooks/phase1-security-hardening.yml
```

### Permission Denied

```bash
# Symptom: "permission denied" when creating secrets
# Ensure you're running as root
whoami  # Should output: root

# Or use sudo
sudo podman secret create aap-db-password -
```

### Authentication Failures

```bash
# Symptom: Container logs show "authentication failed"
# Verify secret is mounted correctly
sudo podman inspect aap-postgresql | jq '.[0].Config.Env' | grep POSTGRESQL_PASSWORD

# Should show: POSTGRESQL_PASSWORD=<value from secret>
# If empty or wrong, check quadlet file for correct Secret= directive

# Check service logs
sudo journalctl -u aap-postgresql.service -n 100 | grep -i password
```

### Secret Content Verification

```bash
# To verify secret contains correct value (use sparingly, security risk)
# Extract secret ID
SECRET_ID=$(sudo podman secret inspect aap-db-password | jq -r '.[0].ID')

# Compare with backup
sudo diff <(sudo cat /var/lib/containers/storage/secrets/sha256/$SECRET_ID) \
           /root/.aap-secrets-backup/aap-db-password.txt
# Should show no differences
```

## Security Best Practices

### Do's ✓

- **Use automated password generation** - Ensures strong, random passwords
- **Backup secrets securely** - Store in `/root/.aap-secrets-backup` with mode 600
- **Rotate regularly** - Follow your organization's password policy
- **Audit secret access** - Monitor who accesses backup files
- **Use system mode** - Secrets in `/var/lib/containers/storage/secrets/` for production
- **Test in non-production first** - Validate secret changes before production deployment

### Don'ts ✗

- **Don't commit secrets to git** - Secrets should never be in version control
- **Don't use weak passwords** - Minimum 32 characters, random
- **Don't share backup files** - Each environment should have unique secrets
- **Don't skip backups** - Lost secrets = locked out of database
- **Don't log secret values** - Use `no_log: true` in Ansible tasks
- **Don't hardcode passwords** - Always use Podman secrets

## Integration with External Secret Management

For production environments, consider integrating with enterprise secret management:

### HashiCorp Vault

```bash
# Retrieve secret from Vault
vault kv get -field=password secret/aap/db-password | \
  sudo podman secret create aap-db-password -
```

### CyberArk

```bash
# Retrieve from CyberArk API
curl -H "Authorization: Bearer $CYBERARK_TOKEN" \
  https://cyberark.example.com/api/Accounts/Get/aap-db-password | \
  jq -r '.Content' | \
  sudo podman secret create aap-db-password -
```

### AWS Secrets Manager

```bash
# Retrieve from AWS Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id aap/db-password \
  --query SecretString \
  --output text | \
  sudo podman secret create aap-db-password -
```

## User Mode vs System Mode

### System Mode (Recommended for Production)

- Secrets stored in: `/var/lib/containers/storage/secrets/`
- Requires: root access
- Persistence: Survives user logout
- Use case: Production deployments, systemd services

```bash
sudo podman secret create aap-db-password -
```

### User Mode (Development/Testing)

- Secrets stored in: `~/.local/share/containers/storage/secrets/`
- Requires: Regular user access
- Persistence: Tied to user session
- Use case: Development, testing, POC

```bash
# As regular user
podman secret create aap-db-password -
```

**Note**: The Containerfile copies quadlet files to `/etc/containers/systemd/`, indicating system mode deployment.

## Compliance and Auditing

### Audit Log

```bash
# Track secret creation/deletion
sudo journalctl -u podman.service | grep secret

# Track who accessed backup files
sudo ausearch -f /root/.aap-secrets-backup/ -i
```

### Compliance Reporting

```bash
# Generate secret inventory
sudo podman secret ls --format "{{.Name}}\t{{.CreatedAt}}\t{{.UpdatedAt}}" | \
  tee aap-secrets-inventory-$(date +%Y%m%d).txt

# Verify no hardcoded passwords remain
grep -r "PASSWORD=redhat" quadlet/*.container
# Should return nothing
```

## Additional Resources

- [Podman Secrets Documentation](https://docs.podman.io/en/latest/markdown/podman-secret.1.html)
- [Quadlet Secrets Integration](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html#secret)
- Project Plan: `/Users/cferman/.claude/plans/lovely-munching-phoenix.md`
- Phase 1 Playbook: `playbooks/phase1-security-hardening.yml`
