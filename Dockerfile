# -------------- Build-time variables --------------
ARG MASTODON_VERSION=3.4.3
ARG MASTODON_REPOSITORY=tootsuite/mastodon

ARG RUBY_VERSION=2.7
ARG NODE_VERSION=14
ARG ALPINE_VERSION=3.14
ARG HARDENED_MALLOC_VERSION=8
ARG LIBICONV_VERSION=1.16

ARG UID=991
ARG GID=991
# ---------------------------------------------------


### Build Mastodon stack base (Ruby + Node)
FROM node:${NODE_VERSION}-alpine${ALPINE_VERSION} as node
FROM ruby:${RUBY_VERSION}-alpine${ALPINE_VERSION} as node-ruby
COPY --from=node /usr/local /usr/local
COPY --from=node /opt /opt


### Build Hardened Malloc
ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION} as build-malloc

ARG HARDENED_MALLOC_VERSION
ARG CONFIG_NATIVE=false

RUN apk --no-cache add build-base git gnupg && cd /tmp \
 && wget -q https://github.com/thestinger.gpg && gpg --import thestinger.gpg \
 && git clone --depth 1 --branch ${HARDENED_MALLOC_VERSION} https://github.com/GrapheneOS/hardened_malloc \
 && cd hardened_malloc && git verify-tag $(git describe --tags) \
 && make CONFIG_NATIVE=${CONFIG_NATIVE}


### Build GNU Libiconv (needed for nokogiri)
ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION} as build-gnulibiconv

ARG LIBICONV_VERSION

RUN apk --no-cache add build-base \
 && wget -q https://ftp.gnu.org/pub/gnu/libiconv/libiconv-${LIBICONV_VERSION}.tar.gz \
 && mkdir /tmp/libiconv && tar xf libiconv-${LIBICONV_VERSION}.tar.gz -C /tmp/libiconv --strip-components 1 \
 && cd /tmp/libiconv && mkdir output && ./configure --prefix=$PWD/output \
 && make -j$(getconf _NPROCESSORS_ONLN) && make install


### Build Mastodon (production environment)
FROM node-ruby as mastodon

COPY --from=build-gnulibiconv /tmp/libiconv/output /usr/local
COPY --from=build-malloc /tmp/hardened_malloc/libhardened_malloc.so /usr/local/lib/

ARG MASTODON_VERSION
ARG MASTODON_REPOSITORY

ARG UID
ARG GID

ENV RUN_DB_MIGRATIONS=true \
    SIDEKIQ_WORKERS=5 \
    BIND=0.0.0.0 \
    RAILS_SERVE_STATIC_FILES=true \
    RAILS_ENV=production \
    NODE_ENV=production \
    PATH="${PATH}:/mastodon/bin" \
    LD_PRELOAD="/usr/local/lib/libhardened_malloc.so"

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
    libxml2 \
    libxslt \
    libpq \
    openssl \
    protobuf \
    s6 \
    tzdata \
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
    postgresql-dev \
    protobuf-dev \
    python3 \
    imagemagick \
# Install Mastodon
 && wget -qO- https://github.com/${MASTODON_REPOSITORY}/archive/v${MASTODON_VERSION}.tar.gz | tar xz --strip 1 \
 && bundle config build.nokogiri --use-system-libraries --with-iconv-lib=/usr/local/lib --with-iconv-include=/usr/local/include \
 && bundle config set --local clean 'true' && bundle config set --local deployment 'true' \
 && bundle config set --local without 'test development' && bundle config set no-cache 'true' \
 && bundle install -j$(getconf _NPROCESSORS_ONLN) \
 && yarn install --pure-lockfile --ignore-engines \
 && OTP_SECRET=precompile_placeholder SECRET_KEY_BASE=precompile_placeholder bundle exec rails assets:precompile \
# Clean
 && npm -g --force cache clean && yarn cache clean \
 && apk del build-dependencies \
# Prepare mastodon user
 && adduser -g ${GID} -u ${UID} --disabled-password --gecos "" mastodon \
 && chown -R mastodon:mastodon /mastodon

COPY --chown=mastodon:mastodon rootfs /

RUN chmod +x /usr/local/bin/* /etc/s6.d/*/* /etc/s6.d/.s6-svscan/*

USER mastodon

VOLUME /mastodon/public/system /mastodon/log

EXPOSE 3000 4000

LABEL maintainer="Wonderfall <wonderfall@protonmail.com>" \
      description="Your self-hosted, globally interconnected microblogging community"

ENTRYPOINT ["/usr/local/bin/run"]

CMD ["/bin/s6-svscan", "/etc/s6.d"]
