# AAP Container Image Management

## Overview

This guide covers container image digest pinning, updates, and management for the AAP image-mode deployment. Digest pinning ensures reproducible, secure deployments by locking images to specific SHA256 digests instead of mutable tags.

## Why Digest Pinning?

### Problems with `:latest` Tags

```ini
# Insecure - tag can point to different images over time
Image=registry.redhat.io/ansible-automation-platform-25/controller-rhel8:latest
```

**Risks:**
- **Inconsistent deployments**: `:latest` changes without notice
- **Silent updates**: Containers pull different images on restart
- **Rollback difficulty**: Can't return to exact previous state
- **Supply chain attacks**: Compromised registries can swap images

### Benefits of Digest Pinning

```ini
# Secure - digest is cryptographically guaranteed
Image=registry.redhat.io/ansible-automation-platform-25/controller-rhel8@sha256:abc123...
```

**Benefits:**
- **Reproducibility**: Same digest = identical image every time
- **Auditability**: Know exactly which image version is running
- **Security**: Detects image tampering
- **Controlled updates**: Explicit action required to update

## Current Image Inventory

| Service | Current Tag | Registry |
|---------|-------------|----------|
| postgresql-15 | latest | registry.redhat.io/rhel9/postgresql-15 |
| redis-6 | latest | registry.redhat.io/rhel9/redis-6 |
| controller | latest | registry.redhat.io/ansible-automation-platform-25/controller-rhel8 |
| gateway | latest | registry.redhat.io/ansible-automation-platform-25/gateway-rhel8 |
| gateway-proxy | latest | registry.redhat.io/ansible-automation-platform-25/gateway-proxy-rhel8 |
| hub | latest | registry.redhat.io/ansible-automation-platform-25/hub-rhel8 |
| hub-web | latest | registry.redhat.io/ansible-automation-platform-25/hub-web-rhel8 |
| eda-controller | latest | registry.redhat.io/ansible-automation-platform-25/eda-controller-rhel8 |
| eda-controller-ui | latest | registry.redhat.io/ansible-automation-platform-25/eda-controller-ui-rhel8 |
| receptor | latest | registry.redhat.io/ansible-automation-platform-25/receptor-rhel8 |
| pcp | latest | registry.redhat.io/rhel9/pcp |
| de-supported | latest | registry.redhat.io/ansible-automation-platform-25/de-supported-rhel8 |
| ee-minimal | latest | registry.redhat.io/ansible-automation-platform-25/ee-minimal-rhel8 |
| ee-supported | latest | registry.redhat.io/ansible-automation-platform-25/ee-supported-rhel8 |

**Total:** 14 images

## Automated Digest Pinning

### Create Ansible Playbook

Create `playbooks/pin-image-digests.yml`:

```yaml
---
- name: Pin AAP Container Images to Digests
  hosts: localhost
  become: false
  gather_facts: false

  vars:
    quadlet_dir: "{{ playbook_dir }}/../quadlet"
    backup_dir: "{{ quadlet_dir }}/.digest-pin-backup-{{ ansible_date_time.iso8601_basic_short }}"

  tasks:
    - name: Check Podman registry authentication
      ansible.builtin.command:
        cmd: podman login --get-login registry.redhat.io
      register: registry_auth
      failed_when: registry_auth.rc != 0
      changed_when: false

    - name: Create backup directory
      ansible.builtin.file:
        path: "{{ backup_dir }}"
        state: directory
        mode: '0755'

    - name: Backup quadlet container files
      ansible.builtin.copy:
        src: "{{ item }}"
        dest: "{{ backup_dir }}/{{ item | basename }}"
        mode: '0644'
      loop: "{{ lookup('fileglob', quadlet_dir + '/*.container', wantlist=True) }}"

    - name: Extract current image references
      ansible.builtin.shell: |
        grep "^Image=" {{ item }} | cut -d= -f2
      register: current_images
      loop: "{{ lookup('fileglob', quadlet_dir + '/*.container', wantlist=True) }}"
      changed_when: false

    - name: Pull images and get digests
      ansible.builtin.shell: |
        podman pull {{ item.stdout }} --quiet
        podman image inspect {{ item.stdout }} --format '{{ '{{' }}.Digest{{ '}}' }}'
      register: image_digests
      loop: "{{ current_images.results }}"
      when: "'@sha256:' not in item.stdout"

    - name: Update quadlet files with digests
      ansible.builtin.replace:
        path: "{{ item.item.item }}"
        regexp: '^Image={{ item.item.stdout | regex_escape }}'
        replace: 'Image={{ item.item.stdout | regex_replace(":latest$", "") }}@{{ item.stdout }}'
      loop: "{{ image_digests.results }}"
      when: item.stdout is defined

    - name: Verify all images are pinned
      ansible.builtin.shell: |
        grep "^Image=" {{ quadlet_dir }}/*.container | grep -v "@sha256:" || true
      register: unpinned_images
      changed_when: false

    - name: Display summary
      ansible.builtin.debug:
        msg: |
          ✓ Image Digest Pinning Complete
          
          Backup: {{ backup_dir }}
          Unpinned images: {{ unpinned_images.stdout_lines | length }}
          
          {% if unpinned_images.stdout_lines %}
          ⚠️  Warning: Some images still use tags:
          {{ unpinned_images.stdout }}
          {% else %}
          ✓ All images successfully pinned to digests
          {% endif %}
```

### Run the Playbook

```bash
# Authenticate to Red Hat registry
podman login registry.redhat.io

# Run digest pinning playbook
ansible-playbook playbooks/pin-image-digests.yml

# Review changes
git diff quadlet/

# Commit if satisfied
git add quadlet/*.container
git commit -m "Pin all container images to SHA256 digests for security and reproducibility"
```

## Manual Digest Pinning

### Step 1: Authenticate to Registry

```bash
# Red Hat registry requires authentication
podman login registry.redhat.io

# Enter your Red Hat credentials or service account
# Username: <your-username>
# Password: <your-password-or-token>
```

### Step 2: Pull Image and Get Digest

```bash
# Pull the image
podman pull registry.redhat.io/ansible-automation-platform-25/controller-rhel8:latest

# Get the digest
DIGEST=$(podman image inspect registry.redhat.io/ansible-automation-platform-25/controller-rhel8:latest \
  --format '{{.Digest}}')

echo $DIGEST
# Output: sha256:abc123def456...
```

### Step 3: Update Quadlet File

```bash
# Before
Image=registry.redhat.io/ansible-automation-platform-25/controller-rhel8:latest

# After
Image=registry.redhat.io/ansible-automation-platform-25/controller-rhel8@sha256:abc123def456...
```

### Step 4: Repeat for All Images

Process all 14 container files following the same pattern.

## Updating Images

### When to Update

- **Security patches**: Red Hat security advisories (RHSA)
- **Bug fixes**: Critical issues in AAP components
- **Feature updates**: New AAP releases
- **Quarterly schedule**: Regular update cycle

### Update Procedure

```bash
# 1. Check for new image versions
podman search --list-tags registry.redhat.io/ansible-automation-platform-25/controller-rhel8 \
  | head -10

# 2. Pull new image
podman pull registry.redhat.io/ansible-automation-platform-25/controller-rhel8:latest

# 3. Get new digest
NEW_DIGEST=$(podman image inspect \
  registry.redhat.io/ansible-automation-platform-25/controller-rhel8:latest \
  --format '{{.Digest}}')

# 4. Update quadlet file
sed -i.bak \
  "s|@sha256:[a-f0-9]*|@$NEW_DIGEST|" \
  quadlet/aap-controller.container

# 5. Test in non-production first
# Deploy to test environment and validate

# 6. Apply to production after validation
```

### Batch Update All Images

```bash
# Re-run the digest pinning playbook
ansible-playbook playbooks/pin-image-digests.yml

# This will:
# - Pull latest images
# - Update all digests
# - Create backup of previous configuration
```

## Verification

### Check Digest Pinning Status

```bash
# Show all image references
grep "^Image=" quadlet/*.container

# Count pinned vs unpinned
echo "Pinned images:"
grep "^Image=.*@sha256:" quadlet/*.container | wc -l

echo "Unpinned images (still using tags):"
grep "^Image=" quadlet/*.container | grep -v "@sha256:" | wc -l
```

### Verify Image Integrity

```bash
# Compare running container digest with quadlet file
RUNNING_DIGEST=$(podman inspect aap-controller --format '{{.Image}}')
CONFIGURED_DIGEST=$(grep "^Image=" quadlet/aap-controller.container | cut -d@ -f2)

if [ "$RUNNING_DIGEST" == "sha256:$CONFIGURED_DIGEST" ]; then
  echo "✓ Image integrity verified"
else
  echo "✗ Warning: Running image differs from configuration"
  echo "Running: $RUNNING_DIGEST"
  echo "Configured: $CONFIGURED_DIGEST"
fi
```

## Registry Mirror Configuration

For air-gapped or disconnected environments:

```bash
# Configure local registry mirror
cat > /etc/containers/registries.conf.d/aap-mirror.conf <<EOF
[[registry]]
location = "registry.redhat.io"
[[registry.mirror]]
location = "mirror.example.com:5000"
insecure = false
EOF

# Pull images through mirror
podman pull registry.redhat.io/ansible-automation-platform-25/controller-rhel8@sha256:abc123...
# Automatically uses mirror.example.com:5000
```

## Troubleshooting

### Digest Not Found

```bash
# Symptom: "manifest unknown" when pulling by digest
# Cause: Digest was deleted from registry (rare but possible)

# Solution: Pull by tag to get new digest
podman pull registry.redhat.io/ansible-automation-platform-25/controller-rhel8:latest
NEW_DIGEST=$(podman image inspect ... --format '{{.Digest}}')
# Update quadlet file with new digest
```

### Authentication Failures

```bash
# Symptom: "unauthorized: authentication required"
# Check authentication status
podman login --get-login registry.redhat.io

# Re-authenticate
podman login registry.redhat.io

# For service accounts (automation)
echo "$REGISTRY_PASSWORD" | podman login registry.redhat.io \
  --username "$REGISTRY_USERNAME" --password-stdin
```

### Slow Image Pulls

```bash
# Enable parallel downloads
cat > /etc/containers/registries.conf.d/99-parallel.conf <<EOF
max_parallel_downloads = 10
EOF

# Use image cache
podman image prune --filter "until=720h"  # Keep images from last 30 days
```

## Image Scanning and Vulnerability Management

### Scan Images for Vulnerabilities

```bash
# Install skopeo and vulnerability scanners
dnf install -y skopeo

# Scan image before pinning
skopeo inspect docker://registry.redhat.io/ansible-automation-platform-25/controller-rhel8:latest

# Check for known vulnerabilities (requires Red Hat subscription)
podman image inspect \
  registry.redhat.io/ansible-automation-platform-25/controller-rhel8@sha256:abc123... \
  --format '{{.Labels}}'
```

### Subscribe to Security Advisories

- Red Hat Security Advisories: https://access.redhat.com/security/security-updates/
- AAP Errata: https://access.redhat.com/downloads/content/package-browser
- CVE monitoring: Track CVEs affecting containerized components

## Best Practices

### Do's ✓

- **Pin all images by digest** - No exceptions for production
- **Test updates in non-production** - Validate new digests before production
- **Document digest changes** - Include reason in git commit messages
- **Automate digest updates** - Use Ansible playbook for consistency
- **Monitor for security updates** - Subscribe to Red Hat advisories
- **Backup before updates** - Always create backup of working configuration

### Don'ts ✗

- **Don't use `:latest` in production** - Breaks reproducibility
- **Don't skip testing** - New digest may have breaking changes
- **Don't ignore security updates** - Update digests promptly for CVE fixes
- **Don't manually edit digests** - Use automation to avoid typos
- **Don't forget to rebuild bootc image** - Digests in quadlet files must match bootc image

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Update AAP Image Digests

on:
  schedule:
    - cron: '0 2 * * 0'  # Weekly on Sunday at 2 AM
  workflow_dispatch:

jobs:
  update-digests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Podman
        run: |
          sudo apt-get update
          sudo apt-get install -y podman

      - name: Authenticate to Red Hat registry
        run: |
          echo "${{ secrets.REGISTRY_PASSWORD }}" | \
            podman login registry.redhat.io \
            --username "${{ secrets.REGISTRY_USERNAME }}" \
            --password-stdin

      - name: Update image digests
        run: |
          ansible-playbook playbooks/pin-image-digests.yml

      - name: Create Pull Request
        uses: peter-evans/create-pull-request@v5
        with:
          title: "chore: Update AAP container image digests"
          body: "Automated weekly update of container image SHA256 digests"
          branch: update-image-digests
```

## Additional Resources

- [Podman Image Management](https://docs.podman.io/en/latest/markdown/podman-image.1.html)
- [Red Hat Container Catalog](https://catalog.redhat.com/software/containers/explore)
- [Skopeo Documentation](https://github.com/containers/skopeo)
- Project Plan: `/Users/cferman/.claude/plans/lovely-munching-phoenix.md`
- Secrets Setup: `docs/SECRETS-SETUP.md`
