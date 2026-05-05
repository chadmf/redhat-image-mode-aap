# AAP Image-Mode Ansible Playbooks

This directory contains Ansible playbooks for implementing security hardening and reliability improvements to the AAP image-mode deployment.

## Prerequisites

```bash
# Install required Ansible collections
ansible-galaxy collection install -r requirements.yml

# Verify Ansible installation
ansible --version  # Requires 2.14+
```

## Playbooks

### Phase 1: Security Hardening

**File:** `phase1-security-hardening.yml`

**Purpose:** Implements critical security improvements:
- Podman secrets management (replaces hardcoded passwords)
- Network segmentation (internal backend network)
- Removes exposed database ports (PostgreSQL 5432, Redis 6379)
- Updates quadlet files with secure configuration

**Usage:**
```bash
# Run as root (required for Podman secrets in system mode)
sudo ansible-playbook playbooks/phase1-security-hardening.yml

# Check what would change (dry-run)
sudo ansible-playbook playbooks/phase1-security-hardening.yml --check
```

**What it does:**
1. Creates Podman secrets: `aap-db-password`, `aap-db-admin-password`
2. Backs up secrets to `/root/.aap-secrets-backup/`
3. Backups existing quadlet files
4. Removes hardcoded passwords from 4 quadlet files
5. Adds `Secret=` directives to quadlet files
6. Creates `aap-backend.network` for data tier isolation
7. Adds dual-network configuration to PostgreSQL and Redis
8. Removes `PublishPort` directives for databases

**Duration:** ~2-3 minutes

**Files Modified:**
- `quadlet/aap-postgresql.container`
- `quadlet/aap-redis.container`
- `quadlet/aap-controller.container`
- `quadlet/aap-hub.container`
- `quadlet/aap-eda-controller.container`
- `quadlet/aap-backend.network` (created)

---

### Phase 2: Reliability Improvements

**File:** `phase2-reliability.yml`

**Purpose:** Adds health checks and resource limits to all containers for improved reliability and resource management.

**Usage:**
```bash
# Run as root
sudo ansible-playbook playbooks/phase2-reliability.yml

# Check what would change
sudo ansible-playbook playbooks/phase2-reliability.yml --check
```

**What it does:**
1. Backups all quadlet container files
2. Adds health check directives to all 14 containers:
   - PostgreSQL: `pg_isready` check
   - Redis: `redis-cli ping` check
   - AAP services: HTTP `/ping` endpoint checks
   - Web UIs: HTTP root checks
3. Adds resource limits to all 14 containers:
   - Memory: `MemoryMax`, `MemoryLow`
   - CPU: `CPUQuota`
4. Validates configuration

**Duration:** ~3-5 minutes

**Files Modified:** All 14 `.container` files

**Resource Allocation:**
- Total Memory: ~16-18GB reserved
- Total CPU: ~12.5 cores (1250%)

---

### Image Digest Pinning (Optional)

**File:** `pin-image-digests.yml` (see `docs/IMAGE-MANAGEMENT.md` for template)

**Purpose:** Replaces `:latest` tags with SHA256 digests for reproducible deployments.

**Usage:**
```bash
# Authenticate to Red Hat registry first
podman login registry.redhat.io

# Run playbook
ansible-playbook playbooks/pin-image-digests.yml
```

## Workflow

### Initial Deployment

```bash
# Step 1: Run Phase 1 (Security)
sudo ansible-playbook playbooks/phase1-security-hardening.yml

# Step 2: Review changes
git diff quadlet/

# Step 3: Run Phase 2 (Reliability)
sudo ansible-playbook playbooks/phase2-reliability.yml

# Step 4: Review changes again
git diff quadlet/

# Step 5: Commit changes
git add quadlet/ playbooks/ docs/
git commit -m "Implement security hardening and reliability improvements"

# Step 6: Update Containerfile (if deploying as bootc image)
# The Containerfile copies quadlet/* to /etc/containers/systemd/
# Rebuild the bootc image to include updated quadlet files

# Step 7: Deploy and verify
sudo systemctl daemon-reload
sudo systemctl start aap-network.service aap-backend.service
sudo systemctl start aap-*.service
```

### Updating Existing Deployment

```bash
# Option 1: Re-run playbooks (safe, idempotent)
sudo ansible-playbook playbooks/phase1-security-hardening.yml
sudo ansible-playbook playbooks/phase2-reliability.yml

# Option 2: Manual updates
# Edit quadlet files directly, then:
sudo systemctl daemon-reload
sudo systemctl restart aap-*.service
```

## Verification

### Verify Phase 1

```bash
# Check secrets exist
sudo podman secret ls | grep aap-

# Check no exposed database ports
sudo ss -tlnp | grep -E "5432|6379"  # Should return nothing

# Check network configuration
sudo podman network ls | grep aap-

# Check services start correctly
sudo systemctl status aap-postgresql.service aap-controller.service
```

### Verify Phase 2

```bash
# Check health check status
sudo podman ps --format "{{.Names}}\t{{.Status}}" | grep aap-
# All should show "healthy" after HealthStartPeriod

# Check resource limits applied
systemctl show aap-controller.service | grep -E "MemoryMax|CPUQuota"

# Monitor resource usage
podman stats --no-stream | grep aap-
```

## Rollback

### Rollback Phase 1

```bash
# Restore from backup (find latest backup directory)
BACKUP_DIR=$(ls -td /Users/cferman/git/redhat-image-mode-aap/quadlet/.backup-* | head -1)
sudo cp $BACKUP_DIR/*.container /etc/containers/systemd/
sudo cp $BACKUP_DIR/*.network /etc/containers/systemd/

# Remove secrets
sudo podman secret rm aap-db-password aap-db-admin-password

# Remove backend network
sudo podman network rm aap-backend

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart aap-*.service
```

### Rollback Phase 2

```bash
# Find latest Phase 2 backup
BACKUP_DIR=$(ls -td /Users/cferman/git/redhat-image-mode-aap/quadlet/.backup-phase2-* | head -1)
sudo cp $BACKUP_DIR/*.container /etc/containers/systemd/

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart aap-*.service
```

## Troubleshooting

### Playbook Fails with "Permission Denied"

```bash
# Ensure running as root
sudo ansible-playbook playbooks/phase1-security-hardening.yml

# Or configure sudo
ansible-playbook playbooks/phase1-security-hardening.yml --ask-become-pass
```

### Playbook Fails with "Collection not found"

```bash
# Install required collections
ansible-galaxy collection install -r playbooks/requirements.yml

# Verify installation
ansible-galaxy collection list | grep community.general
```

### Services Fail to Start After Phase 1

```bash
# Check secrets exist
sudo podman secret ls

# Check service logs
sudo journalctl -u aap-postgresql.service -n 50

# Common issue: Secret not found
# Solution: Re-run Phase 1 playbook
sudo ansible-playbook playbooks/phase1-security-hardening.yml
```

### OOM Kills After Phase 2

```bash
# Check resource usage
podman stats aap-postgresql

# Increase memory limits if needed
# Edit quadlet file or re-run playbook with custom vars
sudo vi /etc/containers/systemd/aap-postgresql.container

# See docs/RESOURCE-TUNING.md for guidance
```

## Variables

### Phase 1 Variables

```yaml
# Override in playbook or via -e flag
vars:
  aap_secrets_backup_dir: /root/.aap-secrets-backup  # Secret backup location
  quadlet_dir: "{{ playbook_dir }}/../quadlet"        # Quadlet files directory
```

### Phase 2 Variables

```yaml
# Override resource limits via extra vars
ansible-playbook playbooks/phase2-reliability.yml \
  -e "container_resources=[{'file': 'aap-postgresql.container', 'memory_max': '8G', 'cpu_quota': '400%'}]"
```

## Best Practices

1. **Always backup before running playbooks** (done automatically)
2. **Test in non-production first** - Validate changes in dev/test environment
3. **Review changes** - Use `git diff` to see what changed
4. **Monitor after deployment** - Watch logs and metrics for issues
5. **Document customizations** - If you modify playbooks, document why
6. **Keep playbooks idempotent** - Safe to run multiple times

## Additional Resources

- **Secrets Management:** `../docs/SECRETS-SETUP.md`
- **Image Management:** `../docs/IMAGE-MANAGEMENT.md`
- **Resource Tuning:** `../docs/RESOURCE-TUNING.md`
- **Implementation Plan:** `/Users/cferman/.claude/plans/lovely-munching-phoenix.md`
- **Ansible Documentation:** https://docs.ansible.com/
- **Podman systemd Units:** https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html
