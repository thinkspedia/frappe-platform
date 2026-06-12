# frappe-sites — shared RWX volume for Frappe site files
# Mounted by: backend, frontend, websocket, all worker tasks
# Access: multi-node-multi-writer (NFS allows concurrent mounts)

id        = "frappe-sites"
name      = "frappe-sites"
type      = "csi"
plugin_id = "org.democratic-csi.nfs-zfs"
namespace = "erpnext-nusakura"

capacity_min = "20GiB"
capacity_max = "50GiB"

capability {
  access_mode     = "multi-node-multi-writer"
  attachment_mode = "file-system"
}

mount_options {
  fs_type     = "nfs"
  mount_flags = ["rw", "hard", "nointr", "timeo=600", "retrans=2"]
}
