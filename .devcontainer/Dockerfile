# Development image for working on the Right to Know theme against
# openaustralia/alaveteli.
#
# Replicates alaveteli's docker/Dockerfile (which we can't build directly
# because Alaveteli is cloned *inside* this container by setup.sh, after the
# image is built). If alaveteli's Dockerfile changes, mirror the change here.

ARG RUBY_VERSION=3.2
FROM ruby:${RUBY_VERSION}-bullseye

ENV DOCKER=1
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y && \
    apt-get install -y \
    elinks \
    ghostscript \
    libmagic-dev \
    pdftk \
    poppler-utils \
    postgresql-client \
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
