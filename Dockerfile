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


### Build Hardened Malloc
ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION} AS build-malloc

ARG HARDENED_MALLOC_TAG
ARG HARDENED_MALLOC_COMMIT
ARG CONFIG_NATIVE=false
ARG VARIANT=light

COPY signing/hardened_malloc.allowed_signers /tmp/allowed_signers

RUN apk --no-cache add build-base git openssh-keygen && cd /tmp \
 && git config --global gpg.ssh.allowedSignersFile /tmp/allowed_signers \
 && git init /tmp/hardened_malloc \
 && cd /tmp/hardened_malloc \
 && git remote add origin https://github.com/GrapheneOS/hardened_malloc \
 && git fetch --depth 1 origin refs/tags/${HARDENED_MALLOC_TAG}:refs/tags/${HARDENED_MALLOC_TAG} \
 && git checkout --detach ${HARDENED_MALLOC_TAG} \
 && test "$(git rev-parse HEAD)" = "${HARDENED_MALLOC_COMMIT}" \
 && git verify-tag ${HARDENED_MALLOC_TAG} \
 && make CONFIG_NATIVE=${CONFIG_NATIVE} VARIANT=${VARIANT}


### Build Mastodon (production environment)
FROM node-ruby AS mastodon

COPY --from=build-malloc /tmp/hardened_malloc/out-light/libhardened_malloc-light.so /usr/local/lib/
COPY patches /tmp/patches/
COPY signing/github-web-flow.gpg /tmp/web-flow.gpg

ARG MASTODON_VERSION
ARG MASTODON_REPOSITORY
ARG MASTODON_COMMIT
ARG MASTODON_GPG_FINGERPRINT

ARG UID
ARG GID

ENV RUN_DB_MIGRATIONS=true \
    SIDEKIQ_WORKERS=5 \
    BIND=0.0.0.0 \
    RAILS_SERVE_STATIC_FILES=true \
    RAILS_ENV=production \
    NODE_ENV=production \
    PATH="${PATH}:/mastodon/bin"

WORKDIR /mastodon

# Install runtime dependencies
RUN apk --no-cache add \
    ca-certificates \
    ffmpeg \
    file \
    git \
    icu-libs \
    imagemagick \
    libidn \
    libstdc++ \
    libxml2 \
    libxslt \
    libpq \
    openssl \
    s6 \
    tzdata \
    vips \
    yaml \
    readline \
    gcompat \
# Install build dependencies
 && apk --no-cache add -t build-dependencies \
    build-base \
    icu-dev \
    libidn-dev \
    libtool \
    libxml2-dev \
    libxslt-dev \
    patch \
    gnupg \
    pkgconf \
    postgresql-dev \
    python3 \
    yaml-dev \
    imagemagick \
# Install Mastodon
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
 && patch -p1 < /tmp/patches/mastodon-vite-blurhash.patch \
 && rm -rf .git \
 && cp -a /tmp/mastodon/. /mastodon \
 && rm -rf /tmp/mastodon /tmp/patches "$GNUPGHOME" /tmp/web-flow.gpg \
 && cd /mastodon \
 && bundle config build.nokogiri --use-system-libraries \
 && bundle config set --local clean 'true' && bundle config set --local deployment 'true' \
 && bundle config set --local without 'test development' && bundle config set no-cache 'true' \
 && bundle install -j$(getconf _NPROCESSORS_ONLN) \
 && rm -f /usr/local/bin/yarn /usr/local/bin/yarnpkg \
 && corepack enable \
 && yarn install --immutable \
 && OTP_SECRET=precompile_placeholder \
    SECRET_KEY_BASE_DUMMY=1 \
    bundle exec rails assets:precompile \
# Clean
 && npm -g --force cache clean && yarn cache clean \
 && apk del build-dependencies \
# Prepare mastodon user
 && addgroup -S -g ${GID} mastodon \
 && adduser -S -D -H -u ${UID} -G mastodon mastodon \
 && chown -R mastodon:mastodon /mastodon

ENV LD_PRELOAD="/usr/local/lib/libhardened_malloc-light.so"

COPY --chown=mastodon:mastodon rootfs /

RUN chmod +x /usr/local/bin/* /etc/s6.d/*/* /etc/s6.d/.s6-svscan/*

USER mastodon

VOLUME /mastodon/public/system /mastodon/log

EXPOSE 3000 4000

LABEL maintainer="Wonderfall <wonderfall@protonmail.com>" \
      description="Your self-hosted, globally interconnected microblogging community"

ENTRYPOINT ["/usr/local/bin/run"]

CMD ["s6-svscan", "/etc/s6.d"]
