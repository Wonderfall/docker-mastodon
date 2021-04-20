ARG RUBY_VERSION=2.7.3
ARG NODE_VERSION=14.6.1
ARG ALPINE_VERSION=3.13

# Build Mastodon stack base (Ruby + Node)
FROM ruby:${RUBY_VERSION}-alpine${ALPINE_VERSION} as node-ruby

RUN wget -q https://unofficial-builds.nodejs.org/download/release/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64-musl.tar.xz \
 && mkdir /opt/node && tar -Jxf node-v$NODE_VERSION-linux-x64-musl.tar.xz -C /opt/node --strip-components 1 \
 && rm node-v$NODE_VERSION-linux-x64-musl.tar.xz


# Build Hardened Malloc
FROM alpine:${ALPINE_VERSION} as build-malloc

ARG HARDENED_MALLOC_VERSION=7

RUN apk --no-cache add build-base && cd /tmp \
 && wget -q https://github.com/GrapheneOS/hardened_malloc/archive/refs/tags/${HARDENED_MALLOC_VERSION}.tar.gz \
 && mkdir hardened_malloc && tar xf ${HARDENED_MALLOC_VERSION}.tar.gz -C hardened_malloc --strip-components 1 \
 && cd hardened_malloc && make


# Build GNU Libiconv (needed for nokogiri)
FROM alpine:${ALPINE_VERSION} as build-gnulibiconv

ARG LIBICONV_VERSION=1.16

RUN apk --no-cache add build-base \
 && wget -q https://ftp.gnu.org/pub/gnu/libiconv/libiconv-${LIBICONV_VERSION}.tar.gz \
 && mkdir /tmp/libiconv && tar xf libiconv-${LIBICONV_VERSION}.tar.gz -C /tmp/libiconv --strip-components 1 \
 && cd /tmp/libiconv && mkdir output && ./configure --prefix=$PWD/output \
 && make -j$(getconf _NPROCESSORS_ONLN) && make install


# Build Mastodon
FROM node-ruby as mastodon

COPY --from=build-gnulibiconv /tmp/libiconv/output /usr/local
COPY --from=build-malloc /tmp/hardened_malloc/libhardened_malloc.so /usr/local/lib/

ENV UID=991 GID=991 \
    RUN_DB_MIGRATIONS=true \
    SIDEKIQ_WORKERS=5 \
    BIND=0.0.0.0 \
    RAILS_SERVE_STATIC_FILES=true \
    RAILS_ENV=production \
    NODE_ENV=production \
    PATH="${PATH}:/opt/node/bin:/mastodon/bin" \
    LD_PRELOAD="/usr/local/lib/libhardened_malloc.so"

ARG MASTODON_VERSION=baed52c2a7d8f91bae3c69150005fc528387785c
ARG MASTODON_REPOSITORY=tootsuite/mastodon

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
 && wget -qO- https://github.com/${MASTODON_REPOSITORY}/archive/${MASTODON_VERSION}.tar.gz | tar xz --strip 1 \
 && bundle config build.nokogiri --use-system-libraries --with-iconv-lib=/usr/local/lib --with-iconv-include=/usr/local/include \
 && bundle config set --local clean 'true' && bundle config set --local deployment 'true' \
 && bundle config set --local without 'test development' && bundle config set no-cache 'true' \
 && bundle install -j$(getconf _NPROCESSORS_ONLN) \
 && npm install -g yarn \
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
