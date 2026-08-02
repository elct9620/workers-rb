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
    WORKERS_APP_DIR=/app

WORKDIR /srv/workers

COPY --from=build ${BUNDLE_PATH} ${BUNDLE_PATH}
COPY --from=build /srv/workers/vendor vendor
COPY Gemfile Gemfile.lock config.ru ./
COPY lib lib

# The Host runs untrusted code, so it holds no more of the machine than it
# needs to answer a request — and now that the databases are somewhere it
# reaches rather than somewhere it writes, that is one directory less.
RUN useradd --create-home --shell /usr/sbin/nologin workers
USER workers

# What Compose holds back the Gateway for is a Node that can serve, which is
# the Host's own answer rather than the fact that it answered: a Host that
# cannot read the shared directory replies here, and replies 503.
HEALTHCHECK --interval=5s --timeout=3s --start-period=15s --retries=5 \
  CMD ["ruby", "-rnet/http", "-e", "exit Net::HTTP.get_response(URI('http://127.0.0.1:9292/_health/ready')).code == '200'"]

EXPOSE 9292
CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:9292"]
