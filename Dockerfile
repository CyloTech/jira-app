FROM repo.cylo.io/baseimage

ENV APEX_CALLBACK=false
ENV JAVA_VERSION jdk8u212-b03
ENV RUN_USER            					appbox
ENV RUN_GROUP           					appbox
ENV USERMAP_UID                             1000
ENV USERMAP_GID                             1000

# https://confluence.atlassian.com/display/JSERVERM/Important+directories+and+files
ENV JIRA_HOME          						/home/appbox/jira
ENV JIRA_INSTALL_DIR   						/opt/atlassian/jira

# This is needed for baseimage to work
RUN mkdir -p /home/appbox/jira


ADD scripts/30_postgresql.sh /etc/my_init.d/30_postgresql.sh
ADD scripts/40_jira.sh /etc/my_init.d/40_jira.sh
RUN chmod +x /etc/my_init.d/30_postgresql.sh
RUN chmod +x /etc/my_init.d/40_jira.sh

# Setup java
COPY sources/slim-java* /usr/local/bin/
COPY scripts/slim-java* /usr/local/bin/

RUN set -eux; \
    ARCH="$(dpkg --print-architecture)"; \
    case "${ARCH}" in \
       ppc64el|ppc64le) \
         ESUM='c9f354430dc83cabfc58a229dddac507e36b475c872c157f91ab3ae50fa21bc5'; \
         BINARY_URL='https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u212-b03/OpenJDK8U-jdk_ppc64le_linux_hotspot_8u212b03.tar.gz'; \
         ;; \
       s390x) \
         ESUM='abb653ec70050a38d8f1e18c23bef64edc825240a7e4620e3b6003005c6b4a51'; \
         BINARY_URL='https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u212-b03/OpenJDK8U-jdk_s390x_linux_hotspot_8u212b03.tar.gz'; \
         ;; \
       amd64|x86_64) \
         ESUM='dd28d6d2cde2b931caf94ac2422a2ad082ea62f0beee3bf7057317c53093de93'; \
         BINARY_URL='https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u212-b03/OpenJDK8U-jdk_x64_linux_hotspot_8u212b03.tar.gz'; \
         ;; \
       *) \
         echo "Unsupported arch: ${ARCH}"; \
         exit 1; \
         ;; \
    esac; \
    curl -Lso /tmp/openjdk.tar.gz ${BINARY_URL}; \
    sha256sum /tmp/openjdk.tar.gz; \
    mkdir -p /opt/java/openjdk; \
    cd /opt/java/openjdk; \
    echo "${ESUM}  /tmp/openjdk.tar.gz" | sha256sum -c -; \
    tar -xf /tmp/openjdk.tar.gz; \
    jdir=$(dirname $(dirname $(find /opt/java/openjdk -name java | grep -v "/jre/bin"))); \
    mv ${jdir}/* /opt/java/openjdk; \
    export PATH="/opt/java/openjdk/bin:$PATH"; \
    apt-get update; apt-get install -y --no-install-recommends binutils; \
    /usr/local/bin/slim-java.sh /opt/java/openjdk; \
    apt-get remove -y binutils; \
    rm -rf ${jdir} /tmp/openjdk.tar.gz;

ENV JAVA_HOME=/opt/java/openjdk \
    PATH="/opt/java/openjdk/bin:$PATH"

# Setup jira
VOLUME ["${JIRA_HOME}"]
WORKDIR $JIRA_HOME

# Expose HTTP port
EXPOSE 80
EXPOSE 5432/tcp

ARG JIRA_VERSION=8.0.0
ARG DOWNLOAD_URL=https://product-downloads.atlassian.com/software/jira/downloads/atlassian-jira-software-${JIRA_VERSION}.tar.gz

RUN mkdir -p                             ${JIRA_INSTALL_DIR} \
    && curl -L --silent                  ${DOWNLOAD_URL} | tar -xz --strip-components=1 -C "${JIRA_INSTALL_DIR}" \
    && chown -R ${RUN_USER}:${RUN_GROUP} ${JIRA_INSTALL_DIR}/ \
    && sed -i -e 's/^JVM_SUPPORT_RECOMMENDED_ARGS=""$/: \${JVM_SUPPORT_RECOMMENDED_ARGS:=""}/g' ${JIRA_INSTALL_DIR}/bin/setenv.sh \
    && sed -i -e 's/^JVM_\(.*\)_MEMORY="\(.*\)"$/: \${JVM_\1_MEMORY:=\2}/g' ${JIRA_INSTALL_DIR}/bin/setenv.sh \
    && sed -i -e 's/port="80"/port="80" secure="${catalinaConnectorSecure}" scheme="${catalinaConnectorScheme}" proxyName="${catalinaConnectorProxyName}" proxyPort="${catalinaConnectorProxyPort}"/' ${JIRA_INSTALL_DIR}/conf/server.xml \
    && sed -i -e 's/Context path=""/Context path="${catalinaContextPath}"/' ${JIRA_INSTALL_DIR}/conf/server.xml \
    && sed -i -e 's/port="8080"/port="80"/g' ${JIRA_INSTALL_DIR}/conf/server.xml \
    && touch /etc/container_id && chmod 666 /etc/container_id

RUN apt install -y libcap2-bin uuid-runtime && \
    setcap cap_net_bind_service=+ep ${JAVA_HOME}/bin/java

# Setup postgres
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y wget gnupg \
 && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
 && echo 'deb http://apt.postgresql.org/pub/repos/apt/ bionic-pgdg main' >> /etc/apt/sources.list

ENV PG_APP_HOME="/etc/docker-postgresql" \
    PG_VERSION=11 \
    PG_USER=postgres \
    PG_HOME=/home/appbox/config/postgresql \
    PG_RUNDIR=/run/postgresql \
    PG_LOGDIR=/home/appbox/logs/postgresql \
    PG_CERTDIR=/etc/postgresql/certs \
    DB_USER=atlassian \
    DB_PASS=atlassian \
    DB_NAME=jira

ENV PG_BINDIR=/usr/lib/postgresql/${PG_VERSION}/bin \
    PG_DATADIR=${PG_HOME}/${PG_VERSION}/main

#COPY --from=add-apt-repositories /etc/apt/trusted.gpg /etc/apt/trusted.gpg
#
#COPY --from=add-apt-repositories /etc/apt/sources.list /etc/apt/sources.list

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y acl sudo \
      postgresql-${PG_VERSION} postgresql-client-${PG_VERSION} postgresql-contrib-${PG_VERSION} \
 && ln -sf ${PG_DATADIR}/postgresql.conf /etc/postgresql/${PG_VERSION}/main/postgresql.conf \
 && ln -sf ${PG_DATADIR}/pg_hba.conf /etc/postgresql/${PG_VERSION}/main/pg_hba.conf \
 && ln -sf ${PG_DATADIR}/pg_ident.conf /etc/postgresql/${PG_VERSION}/main/pg_ident.conf \
 && rm -rf ${PG_HOME} \
 && rm -rf /var/lib/apt/lists/*

COPY scripts/postgres/ ${PG_APP_HOME}/

RUN chown -R appbox:appbox /home/appbox
