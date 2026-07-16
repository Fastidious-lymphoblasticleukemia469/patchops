FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        aptly \
        ca-certificates \
        gnupg \
        nginx \
        openssh-server \
        python3 \
        sudo \
        curl \
        postgresql-client \
        python3-psycopg2 && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /run/sshd /etc/aptly

COPY aptly-entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Aptly data directory (matches production pattern)
VOLUME ["/var/cache/aptly"]

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
