###########################################################################################################
#
# How to build:
#
# docker build -t arkcase/pentaho-ce:latest .
#
###########################################################################################################

ARG PUBLIC_REGISTRY="public.ecr.aws"
ARG BASE_REPO="arkcase/base"
ARG BASE_TAG="8.7.0"
ARG VER="9.4.0.0-343"
ARG BLD="02"
ARG PENTAHO_INSTALL_REPO="arkcase/pentaho-ce-install"
ARG LB_VER="4.20.0"
ARG LB_SRC="https://github.com/liquibase/liquibase/releases/download/v${LB_VER}/liquibase-${LB_VER}.tar.gz"

FROM "${PUBLIC_REGISTRY}/${PENTAHO_INSTALL_REPO}:${VER}" as src

ARG PUBLIC_REGISTRY
ARG BASE_REPO
ARG BASE_TAG

FROM "${PUBLIC_REGISTRY}/${BASE_REPO}:${BASE_TAG}"

ARG VER
ARG LB_VER
ARG LB_SRC

ENV JAVA_HOME="/usr/lib/jvm/jre-11-openjdk"

ARG ACM_GID="10000"
ARG ACM_GROUP="acm"
ARG PENTAHO_PORT="8080"

ENV BASE_DIR="/app"
ENV LOGS_DIR="${BASE_DIR}/logs"
ENV DATA_DIR="${BASE_DIR}/data"
ENV WORK_DIR="${DATA_DIR}/work"
ENV TEMP_DIR="${DATA_DIR}/temp"
ENV LB_DIR="${BASE_DIR}/lb"
ENV LB_TAR="${BASE_DIR}/lb.tar.gz"
ENV PENTAHO_HOME="${BASE_DIR}/pentaho"
ENV PENTAHO_PDI_HOME="${BASE_DIR}/pentaho-pdi"
ENV PENTAHO_SERVER="${PENTAHO_HOME}/pentaho-server"
ENV PENTAHO_TOMCAT="${PENTAHO_SERVER}/tomcat"
ENV PENTAHO_WEBAPP="${PENTAHO_TOMCAT}/webapps/pentaho"
ENV PENTAHO_LICENSES="2023"
ENV PENTAHO_LICENSE_DIR="${PENTAHO_HOME}/licenses"
ENV PENTAHO_LICENSE_ARCHIVE="pentaho-server-licenses-${PENTAHO_SERVER_LICENSES}.zip"
ENV PENTAHO_LICENSE_INSTALLER="${PENTAHO_HOME}/license-installer/license-installer.sh"
ENV PENTAHO_PDI_LICENSE_INSTALLER="${PENTAHO_PDI_HOME}/license-installer/license-installer.sh"
ENV PENTAHO_USER="pentaho"
ENV PENTAHO_UID="1998"
ENV PENTAHO_GROUP="${PENTAHO_USER}"
ENV PENTAHO_GID="${PENTAHO_UID}"
ENV PENTAHO_VERSION="${VER}"

LABEL ORG="Armedia LLC" \
      APP="Pentaho EE" \
      VERSION="1.0" \
      IMAGE_SOURCE=https://github.com/ArkCase/ark_pentaho_ee \
      MAINTAINER="Armedia Devops Team <devops@armedia.com>"

RUN mkdir -p "${BASE_DIR}" && \
    groupadd --system --gid "${ACM_GID}" "${ACM_GROUP}" && \
    groupadd --system --gid "${PENTAHO_GID}" "${PENTAHO_GROUP}" && \
    useradd --system --uid "${PENTAHO_UID}" --gid "${PENTAHO_GID}" --groups "${ACM_GROUP}" --create-home --home-dir "${PENTAHO_HOME}" "${PENTAHO_USER}" 

COPY --from=src --chown=${PENTAHO_USER}:${PENTAHO_GROUP} /home/pentaho/app/pentaho "${PENTAHO_HOME}/"
COPY --from=src --chown=${PENTAHO_USER}:${PENTAHO_GROUP} /home/pentaho/app/pentaho-pdi "${PENTAHO_PDI_HOME}/"

RUN yum -y update && \
    yum -y install \
        java-11-openjdk-devel \
        jq \
        openssl \
        sudo \
        unzip \
        xmlstarlet \
    && \
    yum -y clean all

ENV PATH="${PENTAHO_SERVER}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

COPY entrypoint /

COPY --chown=root:root update-ssl /
COPY --chown=root:root 00-update-ssl /etc/sudoers.d/
COPY "server.xml" "logging.properties" "catalina.properties" "${PENTAHO_TOMCAT}/conf/"
COPY start-pentaho.sh "${PENTAHO_SERVER}/"
COPY --chown=${PENTAHO_USER}:${PENTAHO_GROUP} repository.spring.xml "${PENTAHO_SERVER}/pentaho-solutions/system/"
RUN chmod 0640 /etc/sudoers.d/00-update-ssl && \
    sed -i -e "s;\${ACM_GROUP};${ACM_GROUP};g" /etc/sudoers.d/00-update-ssl && \
    chown "${PENTAHO_USER}:${PENTAHO_GROUP}" "${PENTAHO_TOMCAT}/conf"/* && \
    chmod u=rwX,go=r "${PENTAHO_TOMCAT}/conf"/* && \
    rm -f "${PENTAHO_SERVER}/promptuser.sh" "${PENTAHO_SERVER}"/*.bat "${PENTAHO_SERVER}"/*.js && \
    chmod 0755 "${PENTAHO_SERVER}"/*.sh  && \
    chmod a+r "${PENTAHO_SERVER}/pentaho-solutions/system/repository.spring.xml" 

# Install Liquibase, and add all the drivers
RUN curl -L -o "${LB_TAR}" "${LB_SRC}" && \
    mkdir -p "${LB_DIR}" && \
    tar -C "${LB_DIR}" -xzvf "${LB_TAR}" && \
    rm -rf "${LB_TAR}" && \
    cd "${LB_DIR}" && \
    rm -fv \
        "internal/lib/mssql-jdbc.jar" \
        "internal/lib/ojdbc8.jar" \
        "internal/lib/mariadb-java-client.jar" \
        "internal/lib/postgresql.jar" \
        && \
    ln -sv \
        "${PENTAHO_TOMCAT}/lib"/mysql-connector-j-*.jar \
        "${PENTAHO_TOMCAT}/lib"/mariadb-java-client-*.jar \
        "${PENTAHO_TOMCAT}/lib"/mssql-jdbc-*.jar \
        "${PENTAHO_TOMCAT}/lib"/ojdbc11-*.jar \
        "${PENTAHO_TOMCAT}/lib"/postgresql-*.jar \
        "internal/lib"
COPY --chown=${PENTAHO_USER}:${PENTAHO_GROUP} liquibase.properties "${LB_DIR}/"
COPY --chown=${PENTAHO_USER}:${PENTAHO_GROUP} "sql/${VER}" "${LB_DIR}/pentaho/"

USER "${PENTAHO_USER}"

VOLUME [ "${DATA_DIR}" ]
VOLUME [ "${LOGS_DIR}" ]

EXPOSE "${PENTAHO_PORT}"
WORKDIR "${PENTAHO_SERVER}"
ENTRYPOINT [ "/entrypoint" ]
