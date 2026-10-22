# Development image for working on the Right to Know theme against
# openaustralia/alaveteli.
#
# Replicates alaveteli's docker/Dockerfile (which we can't build directly
# because Alaveteli is cloned *inside* this container by setup.sh, after the
# image is built). If alaveteli's Dockerfile changes, mirror the change here.

# Matches production: Ubuntu 22.04 (jammy) with Ruby built by ruby-build, as rbenv does there (the infrastructure
# repo's ruby_version_production). buildpack-deps is the base the official Ruby images use, so it brings the same
# development libraries for building gems.
FROM buildpack-deps:jammy

ARG RUBY_VERSION=3.4.10
# UTF-8 like production; the official Ruby images set this, buildpack-deps doesn't
ENV LANG=C.UTF-8
ENV DOCKER=1
ENV DEBIAN_FRONTEND=noninteractive

RUN git clone --depth 1 https://github.com/rbenv/ruby-build.git /tmp/ruby-build && \
    /tmp/ruby-build/bin/ruby-build "$RUBY_VERSION" /usr/local && \
    rm -rf /tmp/ruby-build

# Jammy's postgresql-client is 14, whose pg_dump refuses the version 15 server in Dockerfile-postgres, so take the
# client from PGDG at the same major version, as alaveteli's own Dockerfile does.
RUN install -d /usr/share/postgresql-common/pgdg && \
    curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
      https://www.postgresql.org/media/keys/ACCC4CF8.asc && \
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt jammy-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list

RUN apt-get update -y && \
    apt-get install -y \
    elinks \
    ghostscript \
    libmagic-dev \
    pdftk \
    poppler-utils \
    postgresql-client-15 \
    sendmail \
    tnef \
    unrtf \
    mutt

# Wait-for-it
RUN git clone https://github.com/vishnubob/wait-for-it.git /tmp/wait-for-it && \
    chmod +x /tmp/wait-for-it/wait-for-it.sh && \
    ln -s /tmp/wait-for-it/wait-for-it.sh /bin/wait-for-it

WORKDIR /alaveteli
RUN git config --global --add safe.directory /alaveteli && \
    git config --global --add safe.directory /alaveteli/commonlib && \
    git config --global --add safe.directory /alaveteli-themes/righttoknow

# Pin to the last RubyGems 3.x release. RubyGems 4.0 removed the deprecated
# Gem::Specification#has_rdoc= method, which the mysociety/ruby-msg fork's
# gemspec still calls, breaking `bundle`/`Bundler.setup` at boot.
RUN gem update --system 3.7.2

EXPOSE 3000
