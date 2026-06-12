# mariadb-data — exclusive RWO volume for MariaDB data directory
# Mounted by: erpnext-nusakura-mariadb job only
# Access: single-node-writer (only one MariaDB instance writes at a time)

id        = "mariadb-data"
name      = "mariadb-data"
type      = "csi"
plugin_id = "org.democratic-csi.nfs-zfs"
namespace = "erpnext-nusakura"

capacity_min = "20GiB"
capacity_max = "100GiB"

# NFS backend doesn't enforce single-writer at storage level.
# Single-writer guarantee is enforced by Nomad scheduling (only 1 MariaDB allocation).
capability {
  access_mode     = "multi-node-multi-writer"
  attachment_mode = "file-system"
}

mount_options {
  fs_type     = "nfs"
  mount_flags = ["rw", "hard", "nointr", "timeo=600", "retrans=2"]
}
