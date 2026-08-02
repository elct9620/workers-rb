# syntax=docker/dockerfile:1

ARG RUBY_VERSION=3.4
FROM ruby:$RUBY_VERSION-slim AS base

# This image is what an operator runs, never what a change is developed
# against, so the server, the Host, and Bundler all read the environment from
# here rather than falling back to the one a working copy gets. Declared once
# for both stages: gems left out of the build are gems the final image cannot
# be carrying.
ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT=development \
    WORKERS_APP_DIR=/app \
    RACK_ENV=production

WORKDIR /srv/workers

FROM base AS build

# The sandbox gem's msgpack dependency publishes no binary for this platform,
# so it is compiled here and the toolchain never reaches the running image.
RUN apt-get update \
 && apt-get install --no-install-recommends -y build-essential \
 && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install && rm -rf "${BUNDLE_PATH}"/cache

# The guest binary ships as a release asset rather than inside the gem, so it
# is fetched once while building instead of on every boot. What fetches it is
# a development tool, so it is installed in a stage that is left behind: only
# the binary comes out of here, and the lockfile is this stage's to rewrite
# because nothing downstream reads it.
FROM build AS guest

ENV BUNDLE_DEPLOYMENT="" \
    BUNDLE_WITHOUT=""

COPY Rakefile ./
RUN bundle install && bundle exec rake wasm:fetch

FROM base

COPY --from=build ${BUNDLE_PATH} ${BUNDLE_PATH}
COPY --from=guest /srv/workers/vendor vendor
COPY Gemfile Gemfile.lock config.ru ./
COPY lib lib

# The Host runs untrusted code, so it holds no more of the machine than it
# needs to answer a request — and now that the databases are somewhere it
# reaches rather than somewhere it writes, that is one directory less. The id
# is given rather than left to the name, so whatever runs this can see the
# user is not root without resolving anything inside the image.
RUN groupadd --system --gid 1000 workers \
 && useradd workers --uid 1000 --gid 1000 --create-home --shell /usr/sbin/nologin
USER 1000:1000

# What Compose holds back the Gateway for is a Node that can serve, which is
# the Host's own answer rather than the fact that it answered: a Host that
# cannot read the shared directory replies here, and replies 503.
HEALTHCHECK --interval=5s --timeout=3s --start-period=15s --retries=5 \
  CMD ["ruby", "-rnet/http", "-e", "exit Net::HTTP.get_response(URI('http://127.0.0.1:9292/_health/ready')).code == '200'"]

EXPOSE 9292
CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:9292"]
