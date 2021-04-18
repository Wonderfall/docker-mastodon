# wonderfall/mastodon
*Your self-hosted, globally interconnected microblogging community.*

Mastodon [official website](https://joinmastodon.org/) and [source code](https://github.com/tootsuite/mastodon/).

## Why this image?
This non-official image is intended as an **all-in-one** Mastodon **production** image. You should use [the official image](https://hub.docker.com/r/tootsuite/mastodon) for development purpose or if you want scalability.

## Security
Don't run random images from random dudes on the Internet. Ideally, you want to maintain and build it yourself.

## Features
- Rootless image
- Based on Alpine Linux
- Includes [hardened_malloc](https://github.com/GrapheneOS/hardened_malloc)
- Precompiled assets for Mastodon

## Build-time variables
|          Variable         |         Description        |       Default      |
| ------------------------- | -------------------------- | ------------------ |
| **MASTODON_VERSION**      | version/commit of Mastodon |         N/A        |
| **REPOSITORY**            | source of Mastodon         | tootsuite/mastodon |

## Environment variables you should change

|          Variable         |         Description         |       Default      |
| ------------------------- | --------------------------- | ------------------ |
|           **UID**         | user id (rebuild to change) |         991        |
|           **GID**         | group id (rebuild to change)|         991        |
|    **RUN_DB_MIGRATIONS**  | run migrations at startup   |        true        |
|    **SIDEKIQ_WORKERS**    | number of Sidekiq workers   |          5         |

Don't forget to provide [an environment file](https://github.com/tootsuite/mastodon/blob/main/.env.production.sample) for Mastodon itself.

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
Here I use Traefik v2 (already configured to redirect 80 to 443 globally).

```yaml
version: '2.4'

networks:
  http_network:
    external: true

  mastodon_network:
    external: false
    internal: true

services:
  mastodon:
    image: wonderfall/mastodon
    container_name: mastodon
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    env_file: /wherever/docker/mastodon/.env.production
    depends_on:
      - mastodon-db
      - mastodon-redis
    volumes:
      - /wherever/docker/mastodon/data:/mastodon/public/system
      - /wherever/docker/mastodon/logs:/mastodon/log
    labels:
      - traefik.enable=true
      - traefik.http.routers.mastodon-web-secure.entrypoints=https
      - traefik.http.routers.mastodon-web-secure.rule=Host(`domain.tld`)
      - traefik.http.routers.mastodon-web-secure.tls=true
      - traefik.http.routers.mastodon-web-secure.middlewares=hsts-headers@file
      - traefik.http.routers.mastodon-web-secure.tls.certresolver=http
      - traefik.http.routers.mastodon-web-secure.service=mastodon-web
      - traefik.http.services.mastodon-web.loadbalancer.server.port=3000
      - traefik.http.routers.mastodon-streaming-secure.entrypoints=https
      - traefik.http.routers.mastodon-streaming-secure.rule=Host(`domain.tld`) && PathPrefix(`/api/v1/streaming`)
      - traefik.http.routers.mastodon-streaming-secure.tls=true
      - traefik.http.routers.mastodon-streaming-secure.middlewares=hsts-headers@file
      - traefik.http.routers.mastodon-streaming-secure.tls.certresolver=http
      - traefik.http.routers.mastodon-streaming-secure.service=mastodon-streaming
      - traefik.http.services.mastodon-streaming.loadbalancer.server.port=4000
      - traefik.docker.network=http_network
    networks:
      - mastodon_network
      - http_network
 
   mastodon-redis:
    image: redis:alpine
    container_name: mastodon-redis
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    volumes:
      - /wherever/docker/mastodon/redis:/data
    networks:
      - mastodon_network

  mastodon-db:
    image: postgres:9.6-alpine
    container_name: mastodon-db
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    volumes:
      - /wherever/docker/mastodon/db:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=mastodon
      - POSTGRES_DB=mastodon
      - POSTGRES_PASSWORD=supersecretpassword
    networks:
      - mastodon_network
```

*This image has been tested and works great with the [gVisor runtime](https://gvisor.dev/).*
