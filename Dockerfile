FROM mariadb:10.4.7

RUN apt-get update && apt-get -y install cron curl openssh-client

ENV TINI_VERSION v0.17.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini

ADD scripts /usr/local/bin/
RUN chmod 0755 /usr/local/bin/backup.sh /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/tini", "-e", "143", "--", "docker-entrypoint.sh"]
