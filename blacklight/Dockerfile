FROM ruby:3.2

ENV BUNDLE_APP_CONFIG=/usr/local/bundle \
    PATH="/usr/local/bundle/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    nodejs npm build-essential git curl ca-certificates libsqlite3-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY scripts/init_blacklight_simple.sh /usr/local/bin/init_blacklight.sh

ARG SOLR_URL=http://solr:8983/solr/bdsa
ARG RAILS_ADDITIONAL_HOSTS="einstein.neurology.emory.edu,einstein.neurology.emory.edu:3001,localhost,localhost:3000,blacklight,blacklight:3000"
ENV SOLR_URL=$SOLR_URL \
    RAILS_ADDITIONAL_HOSTS=$RAILS_ADDITIONAL_HOSTS

RUN chmod +x /usr/local/bin/init_blacklight.sh

CMD ["bash", "-lc", "init_blacklight.sh"]
