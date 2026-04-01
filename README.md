# wonderfall/mastodon
*Your self-hosted, globally interconnected microblogging community.*

Mastodon [official website](https://joinmastodon.org/) and [source code](https://github.com/mastodon/mastodon/).

## Why this image?
This non-official image is intended as an **all-in-one** (as in monolithic) Mastodon **production** image. You should use [the official image](https://github.com/mastodon/mastodon/pkgs/container/mastodon) for development purpose or if you want scalability.

## Security
Don't run random images from random dudes on the Internet. Ideally, you want to maintain and build it yourself.

Images are scanned every day by [Trivy](https://github.com/aquasecurity/trivy) for OS vulnerabilities. They are rebuilt once a week, so you should often update your images regardless of your Mastodon version.

## Features
- Rootless image
- Based on Alpine Linux
- Includes [hardened_malloc](https://github.com/GrapheneOS/hardened_malloc)
- Precompiled assets for Mastodon

## Tags
- `latest` : latest Mastodon version (or working commit)
- `x.x` : latest Mastodon x.x (e.g. `4.5`)
- `x.x.x` : Mastodon x.x.x (including release candidates)

You can always have a glance [here](https://github.com/users/Wonderfall/packages/container/package/mastodon).

## Build-time variables
|          Variable         |         Description        |       Default      |
| ------------------------- | -------------------------- | ------------------ |
| **MASTODON_VERSION**      | Mastodon release tag       |       `4.5.8`      |
| **MASTODON_REPOSITORY**   | source of Mastodon         | `mastodon/mastodon`|
| **MASTODON_COMMIT**       | expected Mastodon commit   | `38e7bb9b866b5d207a511de093de25536f13e9c4` |
| **MASTODON_GPG_FINGERPRINT** | trusted Mastodon signing key | `968479A1AFF927E37D1A566BB5690EEEBB952194` |
| **RUBY_VERSION**          | Ruby base image tag        |        `3.4`       |
| **NODE_VERSION**          | Node.js base image tag     |        `24`        |
| **ALPINE_VERSION**        | Alpine base image tag      |       `3.23`       |
| **HARDENED_MALLOC_TAG**  | hardened_malloc tag        |   `2026030100`     |
| **HARDENED_MALLOC_COMMIT** | expected hardened_malloc commit | `3bee8d3e0e4fd82b684521891373f40ab4982a5a` |

## Environment variables you should change

|          Variable         |         Description         |       Default      |
| ------------------------- | --------------------------- | ------------------ |
|           **UID**         | user id (rebuild to change) |         991        |
|           **GID**         | group id (rebuild to change)|         991        |
|    **RUN_DB_MIGRATIONS**  | run migrations at startup   |        true        |
|    **SIDEKIQ_WORKERS**    | number of Sidekiq workers   |          5         |

Don't forget to provide [an environment file](https://github.com/mastodon/mastodon/blob/main/.env.production.sample) for Mastodon itself.
Mastodon `4.3+` also requires:
- `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`
- `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`
- `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`

Generate them once with `bundle exec rake db:encryption:init` and keep the values stable.

## Volumes
|          Variable            |         Description        |
| -------------------------    | -------------------------- |
| **/mastodon/public/system**  |         data files         |
| **/mastodon/log**            |            logs            |

## Ports
|              Port            |            Use             |
| -------------------------    | -------------------------- |
| **3000**                     |        Mastodon web        |
| **4000**                     |      Mastodon streaming    |

## docker-compose example
Please use your own settings and adjust this example to your needs.
Networking and reverse-proxy details are intentionally omitted here.

```yaml
services:
  mastodon:
    image: ghcr.io/wonderfall/mastodon
    container_name: mastodon
    runtime: runsc-kvm
    restart: unless-stopped
    cpus: 4
    mem_limit: 6g
    pids_limit: 1024
    read_only: true
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    env_file: /wherever/docker/mastodon/.env.production
    depends_on:
      - mastodon-db
      - mastodon-redis
    volumes:
      - /wherever/docker/mastodon/data:/mastodon/public/system
      - /wherever/docker/mastodon/logs:/mastodon/log
      - /wherever/docker/resolv.conf:/etc/resolv.conf:ro
    tmpfs:
      - /etc/s6.d/.s6-svscan:size=10M,mode=0770,uid=991,gid=991,noexec,nosuid,nodev
      - /etc/s6.d/sidekiq/event:size=10M,mode=0770,uid=991,gid=991,noexec,nosuid,nodev
      - /etc/s6.d/sidekiq/supervise:size=10M,mode=0770,uid=991,gid=991,noexec,nosuid,nodev
      - /etc/s6.d/streaming/event:size=10M,mode=0770,uid=991,gid=991,noexec,nosuid,nodev
      - /etc/s6.d/streaming/supervise:size=10M,mode=0770,uid=991,gid=991,noexec,nosuid,nodev
      - /etc/s6.d/web/event:size=10M,mode=0770,uid=991,gid=991,noexec,nosuid,nodev
      - /etc/s6.d/web/supervise:size=10M,mode=0770,uid=991,gid=991,noexec,nosuid,nodev
      - /tmp:size=256M,mode=0770,uid=991,gid=991,noexec,nosuid,nodev

  mastodon-redis:
    image: redis:7-alpine
    container_name: mastodon-redis
    runtime: runsc-kvm
    restart: unless-stopped
    cpus: 4
    mem_limit: 4g
    pids_limit: 512
    user: 999:1000
    read_only: true
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    volumes:
      - /wherever/docker/mastodon/redis:/data
      - /wherever/docker/resolv.conf:/etc/resolv.conf:ro

  mastodon-db:
    image: postgres:14-alpine
    container_name: mastodon-db
    runtime: runsc-kvm
    restart: unless-stopped
    cpus: 4
    mem_limit: 6g
    pids_limit: 1024
    user: 70:70
    read_only: true
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    volumes:
      - /wherever/docker/mastodon/db:/var/lib/postgresql/data
    tmpfs:
      - /var/run/postgresql:size=50M,mode=0770,uid=70,gid=70,noexec,nosuid,nodev
    environment:
      - POSTGRES_USER=mastodon
      - POSTGRES_DB=mastodon
      - POSTGRES_PASSWORD=supersecretpassword
```

*This image has been tested and works great with the [gVisor runtime](https://gvisor.dev/).*
