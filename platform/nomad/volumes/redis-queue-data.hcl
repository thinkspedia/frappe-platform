# redis-queue-data — exclusive RWO volume for Redis queue persistence
# Mounted by: erpnext-nusakura-redis job (queue instance only)

id        = "redis-queue-data"
name      = "redis-queue-data"
type      = "csi"
plugin_id = "org.democratic-csi.nfs-zfs"
namespace = "erpnext-nusakura"

capacity_min = "2GiB"
capacity_max = "10GiB"

# NFS backend doesn't enforce single-writer at storage level.
# Single-writer guarantee is enforced by Nomad scheduling (only 1 Redis allocation).
capability {
  access_mode     = "multi-node-multi-writer"
  attachment_mode = "file-system"
}

mount_options {
  fs_type     = "nfs"
  mount_flags = ["rw", "hard", "nointr", "timeo=600", "retrans=2"]
}
