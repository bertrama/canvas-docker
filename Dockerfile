FROM ubuntu:16.04

MAINTAINER Jay Luker <jay_luker@harvard.edu>

ARG REVISION=master
ENV RAILS_ENV development
ENV GEM_HOME /opt/canvas/.gems

# add nodejs and recommended ruby repos
RUN apt-get update \
    && apt-get -y install curl software-properties-common sudo \
    && add-apt-repository -y ppa:brightbox/ruby-ng \
    && curl -sL https://deb.nodesource.com/setup_14.x | bash \
    && curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
    && echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list \
    && apt-get update \
    && apt-get install -y ruby2.6 ruby2.6-dev supervisor redis-server \
        zlib1g-dev libxml2-dev libxslt1-dev libsqlite3-dev postgresql \
        postgresql-contrib libpq-dev libxmlsec1-dev curl make g++ git \
        unzip fontforge libicu-dev \
        nodejs yarn unzip fontforge \
    && apt-get clean \
    && rm -Rf /var/cache/apt

# Set the locale to avoid active_model_serializers bundler install failure
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

RUN groupadd -r canvasuser -g 433 && \
    adduser --uid 431 --system --gid 433 --home /opt/canvas canvasuser && \
    adduser canvasuser sudo && \
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

RUN if [ -e /var/lib/gems/$RUBY_MAJOR.0/gems/bundler-* ]; then BUNDLER_INSTALL="-i /var/lib/gems/$RUBY_MAJOR.0"; fi \
  && gem uninstall --all --ignore-dependencies --force $BUNDLER_INSTALL bundler \
  && gem install bundler --no-document -v 2.2.11 \
  && chown -R canvasuser: $GEM_HOME

COPY --chown=canvasuser assets/dbinit.sh /opt/canvas/dbinit.sh
COPY --chown=canvasuser assets/start.sh /opt/canvas/start.sh

COPY assets/supervisord.conf /etc/supervisor/supervisord.conf
COPY assets/pg_hba.conf /etc/postgresql/9.5/main/pg_hba.conf
RUN sed -i "/^#listen_addresses/i listen_addresses='*'" /etc/postgresql/9.5/main/postgresql.conf

USER canvasuser

RUN cd /opt/canvas \
    && git clone https://github.com/instructure/canvas-lms.git \
    && cd canvas-lms \
    && git checkout $REVISION

WORKDIR /opt/canvas/canvas-lms

COPY assets/database.yml config/database.yml
COPY assets/redis.yml config/redis.yml
COPY assets/cache_store.yml config/cache_store.yml
COPY assets/development-local.rb config/environments/development-local.rb
COPY assets/outgoing_mail.yml config/outgoing_mail.yml

RUN for config in amazon_s3 delayed_jobs domain file_store security external_migration \
       ; do cp config/$config.yml.example config/$config.yml \
       ; done

RUN $GEM_HOME/bin/bundle install --jobs 8 --without="mysql"
RUN echo 'workspaces-experimental true' > .yarnrc
RUN yarn install --pure-lockfile --network-concurrency 1

RUN COMPILE_ASSETS_NPM_INSTALL=0 $GEM_HOME/bin/bundle exec rake canvas:compile_assets_dev

RUN mkdir -p log tmp/pids public/assets public/stylesheets/compiled \
    && touch Gemmfile.lock

RUN sudo service postgresql start && \
    /opt/canvas/dbinit.sh && \
    sudo service postgresql stop

# postgres
EXPOSE 5432
# redis
EXPOSE 6379
# canvas
EXPOSE 3000

CMD ["sudo", "-E", "/opt/canvas/start.sh"]
