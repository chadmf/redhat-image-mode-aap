# AAP Container Resource Tuning Guide

## Overview

This guide covers CPU and memory resource limit configuration for AAP containers. Resource limits prevent resource exhaustion, ensure fair allocation, and improve system stability.

## Baseline Configuration (Phase 2)

The Phase 2 playbook configures baseline resource limits suitable for small-to-medium deployments (10-50 concurrent users).

### Resource Allocation Summary

| Service | Memory Max | Memory Low | CPU Quota | Workload Type |
|---------|-----------|-----------|-----------|---------------|
| **Data Tier** |
| PostgreSQL | 4G | 3G | 200% (2 cores) | Database I/O |
| Redis | 1G | 768M | 100% (1 core) | In-memory cache |
| **Application Tier** |
| Controller | 2G | 1536M | 150% (1.5 cores) | Job execution |
| Hub | 2G | 1536M | 150% (1.5 cores) | Content mgmt |
| EDA Controller | 2G | 1536M | 150% (1.5 cores) | Event processing |
| **Presentation Tier** |
| Gateway | 1G | 768M | 100% (1 core) | Reverse proxy |
| Gateway Proxy | 512M | 384M | 50% (0.5 core) | Supporting proxy |
| Hub Web | 1G | 768M | 100% (1 core) | Static UI |
| EDA UI | 1G | 768M | 100% (1 core) | Static UI |
| **Infrastructure** |
| Receptor | 512M | 256M | 50% (0.5 core) | Mesh networking |
| PCP | 256M | 128M | 25% (0.25 core) | Monitoring |
| **Execution Environments** |
| EE Minimal | 512M | 256M | 50% (0.5 core) | Minimal runtime |
| EE Supported | 1G | 512M | 100% (1 core) | Full runtime |
| DE Supported | 512M | 256M | 50% (0.5 core) | Decision engine |

**Total System Requirements:**
- **Memory**: ~16-18GB reserved
- **CPU**: ~12.5 cores (1250%)
- **Recommended Host**: 32GB RAM, 16 CPU cores

## Understanding Resource Limits

### Memory Limits

```ini
[Service]
MemoryMax=2G        # Hard limit - OOM kill if exceeded
MemoryLow=1536M     # Soft reservation - guaranteed allocation
```

- **MemoryMax**: Hard cap - container killed (OOM) if exceeded
- **MemoryLow**: Soft limit - kernel tries to allocate this minimum
- **MemoryHigh**: (optional) Throttle threshold before hitting Max

**Units**: `K` (KB), `M` (MB), `G` (GB), `T` (TB)

### CPU Limits

```ini
CPUQuota=150%       # Maximum CPU usage = 1.5 cores
```

- **CPUQuota**: Maximum CPU time (100% = 1 full core)
- **CPUWeight**: Priority for CPU scheduling (100-10000, default 100)

**Examples:**
- `50%` = half a core
- `100%` = one full core
- `200%` = two full cores
- `400%` = four full cores

## Scaling Up (Production)

For production deployments with 100+ concurrent users or high throughput:

### Data Tier (High Priority)

```ini
# PostgreSQL - Heavy workload
[Service]
MemoryMax=8G
MemoryLow=6G
CPUQuota=400%       # 4 cores
```

```ini
# Redis - Large cache
[Service]
MemoryMax=2G
MemoryLow=1536M
CPUQuota=200%       # 2 cores
```

### Application Tier

```ini
# Controller - More jobs
[Service]
MemoryMax=4G
MemoryLow=3G
CPUQuota=300%       # 3 cores
```

```ini
# Hub - Large content repositories
[Service]
MemoryMax=4G
MemoryLow=3G
CPUQuota=200%       # 2 cores
```

```ini
# EDA Controller - High event volume
[Service]
MemoryMax=4G
MemoryLow=3G
CPUQuota=200%       # 2 cores
```

**Production Total**: ~40-50GB RAM, 20-24 CPU cores

## Scaling Down (Edge/Testing)

For edge deployments, POC, or testing environments:

### Data Tier (Minimal)

```ini
# PostgreSQL - Light workload
[Service]
MemoryMax=2G
MemoryLow=1G
CPUQuota=100%       # 1 core
```

```ini
# Redis - Small cache
[Service]
MemoryMax=512M
MemoryLow=256M
CPUQuota=50%        # 0.5 core
```

### Application Tier

```ini
# Controller/Hub/EDA - Reduced resources
[Service]
MemoryMax=1G
MemoryLow=512M
CPUQuota=100%       # 1 core
```

**Edge/Testing Total**: ~8-10GB RAM, 6-8 CPU cores

## Monitoring Resource Usage

### Real-Time Monitoring

```bash
# Live resource usage (all containers)
podman stats

# Specific container
podman stats aap-controller

# One-time snapshot
podman stats --no-stream | grep aap-
```

**Output:**
```
CONTAINER       CPU %  MEM USAGE / LIMIT  MEM %  NET I/O      BLOCK I/O
aap-postgresql  15%    1.2GB / 4GB       30%    120MB/80MB   50MB/100MB
aap-controller  8%     1.8GB / 2GB       90%    80MB/120MB   20MB/40MB
```

### Historical Monitoring

```bash
# Check systemd resource usage
systemctl status aap-controller.service

# Detailed resource accounting
systemd-cgtop

# Filter to AAP services
systemd-cgtop | grep aap-
```

### Memory Pressure

```bash
# Check for OOM kills
sudo journalctl -u aap-*.service | grep -i oom

# Check memory pressure events
sudo journalctl -u aap-controller.service | grep -i "memory"

# View cgroup memory stats
cat /sys/fs/cgroup/system.slice/aap-controller.service/memory.stat
```

### CPU Throttling

```bash
# Check CPU quota enforcement
systemctl show aap-controller.service | grep CPU

# View CPU throttling events
cat /sys/fs/cgroup/system.slice/aap-controller.service/cpu.stat
```

## Tuning Procedure

### Step 1: Establish Baseline

```bash
# Record baseline resource usage
podman stats --no-stream | grep aap- > /tmp/aap-baseline-$(date +%Y%m%d).txt

# Run typical workload for 24-48 hours
# Monitor peak usage during business hours
```

### Step 2: Analyze Usage Patterns

```bash
# Identify containers hitting limits
sudo journalctl --since "24 hours ago" | grep -E "oom|killed|throttled"

# Check memory high watermark
for service in aap-postgresql aap-controller aap-hub aap-eda-controller; do
  echo "=== $service ==="
  systemctl show $service.service | grep -E "MemoryMax|MemoryCurrent"
done
```

### Step 3: Adjust Limits

```bash
# Edit quadlet file
sudo vi /etc/containers/systemd/aap-controller.container

# Modify [Service] section
[Service]
MemoryMax=4G        # Increased from 2G
MemoryLow=3G        # Increased from 1536M
CPUQuota=200%       # Increased from 150%

# Reload systemd
sudo systemctl daemon-reload

# Restart service to apply new limits
sudo systemctl restart aap-controller.service
```

### Step 4: Validate Changes

```bash
# Verify new limits applied
systemctl show aap-controller.service | grep -E "MemoryMax|CPUQuota"

# Monitor for 24 hours
# Check for OOM kills or throttling

# If stable, apply to other services
```

## Common Scenarios

### Scenario 1: PostgreSQL OOM Kills

**Symptoms:**
```bash
sudo journalctl -u aap-postgresql.service | grep oom
# Output: Memory cgroup out of memory: Killed process 12345 (postgres)
```

**Solution:**
```ini
# Increase PostgreSQL memory limits
[Service]
MemoryMax=8G        # Was 4G
MemoryLow=6G        # Was 3G
```

**Root Cause Analysis:**
```bash
# Check PostgreSQL shared_buffers config
podman exec aap-postgresql psql -U postgres -c "SHOW shared_buffers;"

# Ensure shared_buffers + work_mem + maintenance_work_mem < MemoryMax
```

### Scenario 2: Controller High CPU

**Symptoms:**
```bash
podman stats aap-controller
# CPU %: 148% (constantly near 150% limit)
```

**Solution:**
```ini
# Increase CPU quota
[Service]
CPUQuota=300%       # Was 150%
```

**Alternative:** Check for inefficient jobs or runaway tasks
```bash
# Check for long-running jobs
podman exec aap-controller awx jobs list --status running --order-by=-started
```

### Scenario 3: Hub Content Management Slow

**Symptoms:**
- Slow content uploads/downloads
- High memory usage during sync operations

**Solution:**
```ini
# Increase Hub resources
[Service]
MemoryMax=4G        # Was 2G
MemoryLow=3G        # Was 1536M
CPUQuota=200%       # Was 150%
```

### Scenario 4: Redis Cache Evictions

**Symptoms:**
```bash
# Check Redis memory usage
podman exec aap-redis redis-cli INFO memory | grep maxmemory

# Check eviction count
podman exec aap-redis redis-cli INFO stats | grep evicted_keys
```

**Solution:**
```ini
# Increase Redis memory
[Service]
MemoryMax=2G        # Was 1G
MemoryLow=1536M     # Was 768M
```

## Systemd Resource Control

### Additional Resource Directives

```ini
[Service]
# I/O limits
IOWeight=500                    # I/O scheduling weight (10-1000)
IOReadBandwidthMax=/dev/sda 100M    # Max read throughput
IOWriteBandwidthMax=/dev/sda 50M    # Max write throughput

# Process limits
TasksMax=4096                   # Maximum number of tasks/threads

# CPU affinity
CPUAffinity=0-3                 # Pin to specific CPU cores

# Memory swap
MemorySwapMax=0                 # Disable swap for this service
```

### Real-Time Priority

```ini
# For latency-sensitive services (use sparingly)
[Service]
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=50
```

## Performance Tuning Tips

### PostgreSQL Optimization

```bash
# Tune PostgreSQL for available resources
podman exec aap-postgresql psql -U postgres << EOF
ALTER SYSTEM SET shared_buffers = '1GB';           # 25% of MemoryMax
ALTER SYSTEM SET effective_cache_size = '3GB';     # 75% of MemoryMax
ALTER SYSTEM SET work_mem = '16MB';                # For sorting/joins
ALTER SYSTEM SET maintenance_work_mem = '256MB';   # For VACUUM
SELECT pg_reload_conf();
EOF
```

### Redis Optimization

```bash
# Configure Redis maxmemory
podman exec aap-redis redis-cli CONFIG SET maxmemory 768mb  # 75% of MemoryMax
podman exec aap-redis redis-cli CONFIG SET maxmemory-policy allkeys-lru
```

### Controller Optimization

```bash
# Adjust Controller worker processes based on CPU quota
# CPUQuota=150% → 2 workers
# CPUQuota=300% → 4 workers
# CPUQuota=400% → 6 workers

# Set via environment variable in quadlet file
Environment=ANSIBLE_WORKER_COUNT=4
```

## Resource Presets

### Preset 1: Development/Testing
```bash
# Total: 8-10GB RAM, 6-8 CPUs
ansible-playbook playbooks/phase2-reliability.yml \
  -e preset=development
```

### Preset 2: Small Production
```bash
# Total: 16-18GB RAM, 12-14 CPUs (baseline)
ansible-playbook playbooks/phase2-reliability.yml \
  -e preset=small
```

### Preset 3: Medium Production
```bash
# Total: 32-36GB RAM, 20-24 CPUs
ansible-playbook playbooks/phase2-reliability.yml \
  -e preset=medium
```

### Preset 4: Large Production
```bash
# Total: 64-72GB RAM, 32-40 CPUs
ansible-playbook playbooks/phase2-reliability.yml \
  -e preset=large
```

## Troubleshooting

### High Memory Usage (No OOM)

```bash
# Check for memory leaks
podman top aap-controller -eo pid,comm,rss,vsz

# Restart service to reclaim memory
sudo systemctl restart aap-controller.service
```

### CPU Throttling Issues

```bash
# Check for CPU throttling
cat /sys/fs/cgroup/system.slice/aap-controller.service/cpu.stat | grep throttled

# If throttled_time is high, increase CPUQuota
```

### Unexpected Resource Usage

```bash
# Check what's using resources inside container
podman exec aap-controller top -b -n 1

# Check for zombie processes
podman exec aap-controller ps aux | grep Z
```

## Best Practices

### Do's ✓

- **Start conservative** - Begin with baseline limits, increase as needed
- **Monitor before tuning** - Collect data for 24-48 hours before changes
- **Test limits in non-prod** - Validate resource changes before production
- **Leave headroom** - Set limits 20-30% above peak usage
- **Document changes** - Record why limits were adjusted
- **Use soft limits** - MemoryLow allows flexibility while guaranteeing minimum

### Don'ts ✗

- **Don't over-provision** - Unrestricted resources risk host exhaustion
- **Don't ignore OOM kills** - Address root cause, don't just increase limits
- **Don't set limits too tight** - Leave room for usage spikes
- **Don't forget swap** - Disable swap for production databases
- **Don't tune blindly** - Always base changes on monitoring data
- **Don't skip testing** - Resource changes can impact application behavior

## Additional Resources

- [systemd Resource Control](https://www.freedesktop.org/software/systemd/man/systemd.resource-control.html)
- [Podman systemd Units](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [cgroup v2 Documentation](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)
- Project Plan: `/Users/cferman/.claude/plans/lovely-munching-phoenix.md`
- Phase 2 Playbook: `playbooks/phase2-reliability.yml`
