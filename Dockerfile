# syntax=docker/dockerfile:1
FROM ruby:3.4-slim AS build

ENV BUNDLE_PATH=/usr/local/bundle

# The sandbox gem's msgpack dependency publishes no binary for this platform,
# so it is compiled here and the toolchain never reaches the running image.
RUN apt-get update \
 && apt-get install --no-install-recommends -y build-essential \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /srv/workers

COPY Gemfile Gemfile.lock ./
RUN bundle install && rm -rf "${BUNDLE_PATH}"/cache

# The guest binary ships as a release asset rather than inside the gem, so it
# is fetched once while building instead of on every boot.
COPY Rakefile ./
RUN bundle exec rake wasm:fetch

FROM ruby:3.4-slim

ENV BUNDLE_PATH=/usr/local/bundle \
    WORKERS_APP_DIR=/app \
    WORKERS_DB_DIR=/data

WORKDIR /srv/workers

COPY --from=build ${BUNDLE_PATH} ${BUNDLE_PATH}
COPY --from=build /srv/workers/vendor vendor
COPY Gemfile Gemfile.lock config.ru ./
COPY lib lib

# The Host runs untrusted code, so it holds no more of the machine than it
# needs to answer a request. The database mount is created here rather than
# left to the volume: a volume takes the ownership of the directory it covers,
# and the Host is not the user that would otherwise own it.
RUN useradd --create-home --shell /usr/sbin/nologin workers \
 && install -d -o workers -g workers /data
USER workers

# Answering at all is the signal — a path matching no Tenant is a 404 from a
# Host that is up.
HEALTHCHECK --interval=5s --timeout=3s --start-period=15s --retries=5 \
  CMD ["ruby", "-rnet/http", "-e", "Net::HTTP.get_response(URI('http://127.0.0.1:9292/'))"]

EXPOSE 9292
CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:9292"]
