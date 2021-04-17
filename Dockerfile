FROM alpine:3.13 as build-malloc

ARG HARDENED_MALLOC_VERSION=7

RUN apk -U upgrade && apk add build-base && cd /tmp \
 && wget -q https://github.com/GrapheneOS/hardened_malloc/archive/refs/tags/${HARDENED_MALLOC_VERSION}.tar.gz \
 && mkdir hardened_malloc && tar xf ${HARDENED_MALLOC_VERSION}.tar.gz -C hardened_malloc --strip-components 1 \
 && cd hardened_malloc && make

FROM ruby:2.7.3-alpine3.13

COPY --from=build-malloc /tmp/hardened_malloc/libhardened_malloc.so /usr/local/lib/

ARG MASTODON_VERSION=baed52c2a7d8f91bae3c69150005fc528387785c
ARG MASTODON_REPOSITORY=tootsuite/mastodon
ARG LIBICONV_VERSION=1.16
ARG NODE_VERSION=14.16.1

ENV UID=991 GID=991 \
    RUN_DB_MIGRATIONS=true \
    SIDEKIQ_WORKERS=5 \
    BIND=0.0.0.0 \
    RAILS_SERVE_STATIC_FILES=true \
    RAILS_ENV=production \
    NODE_ENV=production \
    PATH="${PATH}:/opt/node/bin:/mastodon/bin" \
    LD_PRELOAD="/usr/local/lib/libhardened_malloc.so"

WORKDIR /mastodon

# Install dependencies
RUN wget -q https://unofficial-builds.nodejs.org/download/release/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64-musl.tar.xz \
 && mkdir /opt/node && tar -Jxf node-v$NODE_VERSION-linux-x64-musl.tar.xz -C /opt/node --strip-components 1 \
 && rm node-v$NODE_VERSION-linux-x64-musl.tar.xz \
 && apk -U upgrade \
 && apk add \
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
    su-exec \
    tzdata \
    yaml \
    readline \
    gcompat \

# Install build dependencies
 && apk add -t build-dependencies \
    build-base \
    icu-dev \
    libidn-dev \
    libtool \
    libxml2-dev \
    libxslt-dev \
    postgresql-dev \
    protobuf-dev \
    python3 \

# Update CA certificates
 && update-ca-certificates \

# Install GNU Libiconv
 && wget http://ftp.gnu.org/pub/gnu/libiconv/libiconv-${LIBICONV_VERSION}.tar.gz -O /tmp/libiconv-${LIBICONV_VERSION}.tar.gz \
 && mkdir /tmp/src && tar xzf /tmp/libiconv-${LIBICONV_VERSION}.tar.gz -C /tmp/src && rm /tmp/libiconv-${LIBICONV_VERSION}.tar.gz \
 && cd /tmp/src/libiconv-${LIBICONV_VERSION} \
 && ./configure --prefix=/usr/local \
 && make -j$(getconf _NPROCESSORS_ONLN) && make install && libtool --finish /usr/local/lib \

# Install Mastodon
 && cd /mastodon \
 && wget -qO- https://github.com/${MASTODON_REPOSITORY}/archive/${MASTODON_VERSION}.tar.gz | tar xz --strip 1 \
 && bundle config build.nokogiri --use-system-libraries --with-iconv-lib=/usr/local/lib --with-iconv-include=/usr/local/include \
 && bundle config set --local clean 'true' && bundle config set --local deployment 'true' \
 && bundle config set --local without 'test development' && bundle config set no-cache 'true' \
 && bundle install -j$(getconf _NPROCESSORS_ONLN) \
 && npm install -g yarn \
 && yarn install --pure-lockfile --ignore-engines \

# Precompile Mastodon assets
 && OTP_SECRET=precompile_placeholder SECRET_KEY_BASE=precompile_placeholder bundle exec rails assets:precompile \

# Clean
 && npm -g --force cache clean && yarn cache clean \
 && apk del build-dependencies \
 && rm -rf /var/cache/apk/* /tmp/src

COPY rootfs /

RUN chmod +x /usr/local/bin/* /etc/s6.d/*/* /etc/s6.d/.s6-svscan/*

VOLUME /mastodon/public/system /mastodon/log

EXPOSE 3000 4000

LABEL maintainer="Wonderfall <wonderfall@targaryen.house>" \
      description="Your self-hosted, globally interconnected microblogging community"

ENTRYPOINT ["/usr/local/bin/run"]
CMD ["/bin/s6-svscan", "/etc/s6.d"]
