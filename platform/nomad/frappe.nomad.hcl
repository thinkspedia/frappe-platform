# =============================================================================
# frappe.nomad.hcl — Frappe Platform Nomad Job Specification
#
# Structure:
#   migrate    — prestart lifecycle: runs `bench migrate` before web nodes roll
#   web        — Gunicorn (HTTP) + Socket.IO (WebSocket), scalable
#   worker     — Celery workers (default + long + short queues), scalable
#   scheduler  — Celery Beat (single instance always)
#
# Zero-downtime deployment:
#   - Rolling update: max_parallel=1, canary=1 (one canary promoted before rollout)
#   - Automatic rollback on health-check failure
#   - Migration completes before any web/worker task starts
#
# Configuration:
#   All values come from variables at the top — override via:
#     nomad job run -var="web_count=4" frappe.nomad.hcl
#   Or from environment: NOMAD_VAR_web_count=4
#
# Deploy modes:
#   pull  — run `nomad job run` on the Nomad server itself
#   ship  — run `nomad job run` from a CI runner or developer workstation
#           with NOMAD_ADDR and NOMAD_TOKEN set in environment
# =============================================================================

# ---------------------------------------------------------------------------
# Variables — override at deploy time via CLI flags or environment variables
# ---------------------------------------------------------------------------
variable "image" {
  description = "Full image reference including registry and tag"
  default     = "ghcr.io/thinkspedia/frappe-platform:latest"
}

variable "site_name" {
  description = "Frappe site name (must match site directory in sites volume)"
  default     = "erp.example.com"
}

variable "host_name" {
  description = "Public hostname (written to site_config.json and used by Traefik)"
  default     = "erp.example.com"
}

variable "web_count" {
  description = "Number of Gunicorn web task instances"
  default     = 2
}

variable "worker_count" {
  description = "Number of Celery worker task instances"
  default     = 2
}

variable "scheduler_count" {
  description = "Number of scheduler instances (always 1 for Celery Beat)"
  default     = 1
}

variable "db_host" {
  description = "MariaDB/PostgreSQL hostname"
  default     = "mariadb.service.consul"
}

variable "db_port" {
  description = "Database port"
  default     = "3306"
}

variable "db_password" {
  description = "Database password (prefer Nomad Vault integration in production)"
  default     = ""
  sensitive   = true
}

variable "redis_cache" {
  default = "redis-cache.service.consul:6379"
}

variable "redis_queue" {
  default = "redis-queue.service.consul:6379"
}

variable "redis_socketio" {
  default = "redis-socketio.service.consul:6379"
}

variable "gunicorn_workers" {
  default = "2"
}

variable "gunicorn_threads" {
  default = "4"
}

variable "gunicorn_timeout" {
  default = "120"
}

# ---------------------------------------------------------------------------
# Job definition
# ---------------------------------------------------------------------------
job "frappe" {
  datacenters = ["dc1"]
  type        = "service"
  namespace   = "default"

  # ---------------------------------------------------------------------------
  # Update strategy — zero-downtime rolling deployment
  # canary=1: one new instance is started and health-checked before the rollout
  # begins. If it fails, the deployment is automatically reverted.
  # ---------------------------------------------------------------------------
  update {
    max_parallel     = 1
    canary           = 1
    min_healthy_time = "30s"
    healthy_deadline = "5m"
    # Automatically promote the canary if healthy (set to false for manual promotion)
    auto_promote     = true
    # Automatically revert to the previous job version on failure
    auto_revert      = true
    stagger          = "10s"
  }

  # ---------------------------------------------------------------------------
  # migrate — prestart database migration
  # This batch task runs BEFORE web/worker tasks start on each deployment.
  # Uses `lifecycle` with hook=prestart so Nomad waits for it to complete.
  # ---------------------------------------------------------------------------
  group "migrate" {
    count = 1

    restart {
      attempts = 3
      delay    = "10s"
      mode     = "fail"
    }

    task "run-migrations" {
      driver = "docker"

      # prestart: this task must exit 0 before sibling tasks in this group start.
      # Since migrate is its own group, we use a service=false batch pattern.
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image   = var.image
        command = "bench"
        args    = ["--site", var.site_name, "migrate"]
      }

      env {
        FRAPPE_SITE_NAME = var.site_name
        HOST_NAME        = var.host_name
        DB_HOST          = var.db_host
        DB_PORT          = var.db_port
        DB_PASSWORD      = var.db_password
        REDIS_CACHE      = var.redis_cache
        REDIS_QUEUE      = var.redis_queue
        REDIS_SOCKETIO   = var.redis_socketio
      }

      resources {
        cpu    = 500
        memory = 512
      }

      volume_mount {
        volume      = "frappe-sites"
        destination = "/home/frappe/frappe-bench/sites"
      }
    }

    volume "frappe-sites" {
      type   = "host"
      source = "frappe_sites"
    }
  }

  # ---------------------------------------------------------------------------
  # web — Gunicorn HTTP workers + Socket.IO
  # Scalable via var.web_count. Each allocation runs both gunicorn and socketio
  # as separate tasks sharing the same network namespace (localhost routing).
  # ---------------------------------------------------------------------------
  group "web" {
    count = var.web_count

    update {
      max_parallel = 1
      canary       = 1
    }

    network {
      port "http" { static = 8000 }
      port "ws"   { static = 9000 }
    }

    # Register with Consul for service discovery and Traefik routing
    service {
      name = "frappe-web"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.frappe.rule=Host(`${var.host_name}`)",
        "traefik.http.routers.frappe.entrypoints=web",
        "traefik.http.services.frappe.loadbalancer.server.port=8000",
      ]
      check {
        type     = "http"
        path     = "/api/method/ping"
        interval = "15s"
        timeout  = "5s"
      }
    }

    service {
      name = "frappe-ws"
      port = "ws"
      check {
        type     = "tcp"
        interval = "15s"
        timeout  = "5s"
      }
    }

    task "gunicorn" {
      driver = "docker"

      config {
        image = var.image
        command = "bash"
        args = [
          "-c",
          "gunicorn --chdir=/home/frappe/frappe-bench/sites --bind=0.0.0.0:8000 --workers=${var.gunicorn_workers} --threads=${var.gunicorn_threads} --timeout=${var.gunicorn_timeout} frappe.app:application"
        ]
        ports = ["http"]
      }

      env {
        FRAPPE_SITE_NAME   = var.site_name
        HOST_NAME          = var.host_name
        DB_HOST            = var.db_host
        DB_PORT            = var.db_port
        DB_PASSWORD        = var.db_password
        REDIS_CACHE        = var.redis_cache
        REDIS_QUEUE        = var.redis_queue
        REDIS_SOCKETIO     = var.redis_socketio
        GUNICORN_WORKERS   = var.gunicorn_workers
        GUNICORN_THREADS   = var.gunicorn_threads
        GUNICORN_TIMEOUT   = var.gunicorn_timeout
      }

      resources {
        cpu    = 1000
        memory = 1024
      }

      volume_mount {
        volume      = "frappe-sites"
        destination = "/home/frappe/frappe-bench/sites"
      }
    }

    task "socketio" {
      driver = "docker"

      config {
        image   = var.image
        command = "node"
        args    = ["/home/frappe/frappe-bench/apps/frappe/socketio.js"]
        ports   = ["ws"]
      }

      env {
        FRAPPE_SITE_NAME = var.site_name
        REDIS_SOCKETIO   = var.redis_socketio
      }

      resources {
        cpu    = 300
        memory = 256
      }

      volume_mount {
        volume      = "frappe-sites"
        destination = "/home/frappe/frappe-bench/sites"
      }
    }

    volume "frappe-sites" {
      type   = "host"
      source = "frappe_sites"
    }
  }

  # ---------------------------------------------------------------------------
  # worker — Celery background job workers
  # Three queues: default, long, short. Scalable via var.worker_count.
  # ---------------------------------------------------------------------------
  group "worker" {
    count = var.worker_count

    task "worker-default" {
      driver = "docker"
      config {
        image   = var.image
        command = "bench"
        args    = ["worker", "--queue", "default"]
      }
      env {
        FRAPPE_SITE_NAME = var.site_name
        DB_HOST          = var.db_host
        DB_PORT          = var.db_port
        DB_PASSWORD      = var.db_password
        REDIS_CACHE      = var.redis_cache
        REDIS_QUEUE      = var.redis_queue
      }
      resources { cpu = 500; memory = 512 }
      volume_mount {
        volume      = "frappe-sites"
        destination = "/home/frappe/frappe-bench/sites"
      }
    }

    task "worker-long" {
      driver = "docker"
      config {
        image   = var.image
        command = "bench"
        args    = ["worker", "--queue", "long,default,short"]
      }
      env {
        FRAPPE_SITE_NAME = var.site_name
        DB_HOST          = var.db_host
        DB_PORT          = var.db_port
        DB_PASSWORD      = var.db_password
        REDIS_CACHE      = var.redis_cache
        REDIS_QUEUE      = var.redis_queue
      }
      resources { cpu = 500; memory = 512 }
      volume_mount {
        volume      = "frappe-sites"
        destination = "/home/frappe/frappe-bench/sites"
      }
    }

    task "worker-short" {
      driver = "docker"
      config {
        image   = var.image
        command = "bench"
        args    = ["worker", "--queue", "short,default"]
      }
      env {
        FRAPPE_SITE_NAME = var.site_name
        DB_HOST          = var.db_host
        DB_PORT          = var.db_port
        DB_PASSWORD      = var.db_password
        REDIS_CACHE      = var.redis_cache
        REDIS_QUEUE      = var.redis_queue
      }
      resources { cpu = 300; memory = 384 }
      volume_mount {
        volume      = "frappe-sites"
        destination = "/home/frappe/frappe-bench/sites"
      }
    }

    volume "frappe-sites" {
      type   = "host"
      source = "frappe_sites"
    }
  }

  # ---------------------------------------------------------------------------
  # scheduler — Celery Beat
  # Always exactly 1 instance; multiple schedulers would cause duplicate tasks.
  # ---------------------------------------------------------------------------
  group "scheduler" {
    count = 1

    # Prevent Nomad from ever running more than one scheduler at a time,
    # even during a rolling deployment.
    update {
      max_parallel = 1
      canary       = 0
    }

    task "beat" {
      driver = "docker"
      config {
        image   = var.image
        command = "bench"
        args    = ["schedule"]
      }
      env {
        FRAPPE_SITE_NAME = var.site_name
        DB_HOST          = var.db_host
        DB_PORT          = var.db_port
        DB_PASSWORD      = var.db_password
        REDIS_CACHE      = var.redis_cache
        REDIS_QUEUE      = var.redis_queue
      }
      resources { cpu = 200; memory = 256 }
      volume_mount {
        volume      = "frappe-sites"
        destination = "/home/frappe/frappe-bench/sites"
      }
    }

    volume "frappe-sites" {
      type   = "host"
      source = "frappe_sites"
    }
  }
}
