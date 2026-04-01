# -------------- Build-time variables --------------
ARG MASTODON_VERSION=4.5.8
ARG MASTODON_REPOSITORY=mastodon/mastodon
ARG MASTODON_COMMIT=38e7bb9b866b5d207a511de093de25536f13e9c4
ARG MASTODON_GPG_FINGERPRINT=968479A1AFF927E37D1A566BB5690EEEBB952194

ARG RUBY_VERSION=3.4
ARG NODE_VERSION=24
ARG ALPINE_VERSION=3.23
ARG HARDENED_MALLOC_TAG=2026030100
ARG HARDENED_MALLOC_COMMIT=3bee8d3e0e4fd82b684521891373f40ab4982a5a

ARG UID=991
ARG GID=991
# ---------------------------------------------------


### Build Mastodon stack base (Ruby + Node)
FROM node:${NODE_VERSION}-alpine${ALPINE_VERSION} AS node
FROM ruby:${RUBY_VERSION}-alpine${ALPINE_VERSION} AS node-ruby
COPY --from=node /usr/local /usr/local
COPY --from=node /opt /opt


### Shared runtime base
FROM node-ruby AS runtime-base

ENV RUN_DB_MIGRATIONS=true \
    SIDEKIQ_WORKERS=5 \
    BIND=0.0.0.0 \
    RAILS_SERVE_STATIC_FILES=true \
    RAILS_ENV=production \
    NODE_ENV=production \
    PATH="${PATH}:/mastodon/bin"

WORKDIR /mastodon

RUN apk --no-cache add \
    ca-certificates \
    ffmpeg \
    file \
    icu-libs \
    imagemagick \
    libidn \
    libpq \
    libstdc++ \
    libxml2 \
    libxslt \
    openssl \
    readline \
    s6 \
    tzdata \
    vips \
    yaml \
    gcompat


### Build hardened_malloc
ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION} AS build-malloc

ARG HARDENED_MALLOC_TAG
ARG HARDENED_MALLOC_COMMIT
ARG CONFIG_NATIVE=false
ARG VARIANT=light

COPY signing/hardened_malloc.allowed_signers /tmp/allowed_signers

RUN apk --no-cache add build-base git openssh-keygen \
 && git config --global gpg.ssh.allowedSignersFile /tmp/allowed_signers \
 && git init -q /tmp/hardened_malloc \
 && cd /tmp/hardened_malloc \
 && git remote add origin https://github.com/GrapheneOS/hardened_malloc \
 && git fetch --depth 1 origin refs/tags/${HARDENED_MALLOC_TAG}:refs/tags/${HARDENED_MALLOC_TAG} \
 && git checkout --detach ${HARDENED_MALLOC_TAG} \
 && test "$(git rev-parse HEAD)" = "${HARDENED_MALLOC_COMMIT}" \
 && git verify-tag ${HARDENED_MALLOC_TAG} \
 && make CONFIG_NATIVE=${CONFIG_NATIVE} VARIANT=${VARIANT}


### Fetch and verify Mastodon source
ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION} AS mastodon-source

ARG MASTODON_VERSION
ARG MASTODON_REPOSITORY
ARG MASTODON_COMMIT
ARG MASTODON_GPG_FINGERPRINT

COPY patches/mastodon-vite-blurhash.patch /tmp/mastodon-vite-blurhash.patch
COPY signing/github-web-flow.gpg /tmp/web-flow.gpg

RUN apk --no-cache add git gnupg patch \
 && GNUPGHOME="$(mktemp -d)" \
 && export GNUPGHOME \
 && gpg --batch --with-colons --import-options show-only --import /tmp/web-flow.gpg \
    | awk -F: '$1 == "fpr" { print $10 }' \
    | grep -Fqx "${MASTODON_GPG_FINGERPRINT}" \
 && gpg --batch --import /tmp/web-flow.gpg \
 && git init -q /tmp/mastodon \
 && cd /tmp/mastodon \
 && git remote add origin https://github.com/${MASTODON_REPOSITORY}.git \
 && git fetch --depth 1 origin refs/tags/v${MASTODON_VERSION}:refs/tags/v${MASTODON_VERSION} \
 && git checkout --detach v${MASTODON_VERSION} \
 && test "$(git rev-parse HEAD)" = "${MASTODON_COMMIT}" \
 && git verify-commit HEAD \
 && patch -p1 < /tmp/mastodon-vite-blurhash.patch \
 && rm -rf .git "$GNUPGHOME" /tmp/web-flow.gpg /tmp/mastodon-vite-blurhash.patch


### Build Mastodon application and assets
FROM runtime-base AS build-app

COPY --from=mastodon-source /tmp/mastodon /mastodon

RUN apk --no-cache add \
    build-base \
    git \
    icu-dev \
    libidn-dev \
    libtool \
    libxml2-dev \
    libxslt-dev \
    pkgconf \
    postgresql-dev \
    python3 \
    yaml-dev \
 && bundle config build.nokogiri --use-system-libraries \
 && bundle config set --local clean 'true' \
 && bundle config set --local deployment 'true' \
 && bundle config set --local without 'test development' \
 && bundle config set no-cache 'true' \
 && bundle install -j$(getconf _NPROCESSORS_ONLN) \
 && rm -f /usr/local/bin/yarn /usr/local/bin/yarnpkg \
 && corepack enable \
 && yarn install --immutable \
 && OTP_SECRET=precompile_placeholder \
    SECRET_KEY_BASE_DUMMY=1 \
    bundle exec rails assets:precompile \
 && npm -g --force cache clean \
 && yarn cache clean


### Final image
FROM runtime-base AS mastodon

ARG UID
ARG GID

RUN addgroup -S -g ${GID} mastodon \
 && adduser -S -D -H -u ${UID} -G mastodon mastodon

COPY --from=build-malloc /tmp/hardened_malloc/out-light/libhardened_malloc-light.so /usr/local/lib/
COPY --from=build-app /usr/local/bundle /usr/local/bundle
COPY --from=build-app /mastodon /mastodon
COPY rootfs/usr/local/bin/run /usr/local/bin/run
COPY rootfs/etc/s6.d /etc/s6.d

ENV LD_PRELOAD="/usr/local/lib/libhardened_malloc-light.so"

# Keep application and init code root-owned; only runtime data stays writable.
RUN mkdir -p /mastodon/public/system /mastodon/log /mastodon/tmp \
 && chown -R ${UID}:${GID} /mastodon/public/system /mastodon/log /mastodon/tmp \
 && chmod 755 /usr/local/bin /usr/local/bin/run \
 && chmod -R 755 /etc/s6.d

USER mastodon

VOLUME /mastodon/public/system /mastodon/log

EXPOSE 3000 4000

LABEL maintainer="Wonderfall <wonderfall@protonmail.com>" \
      description="Your self-hosted, globally interconnected microblogging community"

ENTRYPOINT ["/usr/local/bin/run"]

CMD ["s6-svscan", "/etc/s6.d"]
