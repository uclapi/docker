FROM ubuntu:18.04

#################################
######## Main Parameters ########
#################################

ENV ORACLE_VERSION 12_2
ENV ORACLE_SO_VERSION 12.1
ENV ORACLE_INSTANTCLIENT_BASIC_URL https://s3.eu-west-2.amazonaws.com/uclapi-static/instantclient-basic-linux.x64-12.2.0.1.0.zip
ENV ORACLE_INSTANTCLIENT_SDK_URL https://s3.eu-west-2.amazonaws.com/uclapi-static/instantclient-sdk-linux.x64-12.2.0.1.0.zip

ENV ORACLE_INSTALL_DIR /opt/oracle
ENV ORACLE_HOME ${ORACLE_INSTALL_DIR}/instantclient_${ORACLE_VERSION}

ENV UCLAPI_GIT_ADDRESS https://github.com/uclapi/uclapi

ARG UCLAPI_BRANCH
ENV UCLAPI_BRANCH ${UCLAPI_BRANCH}
ARG UCLAPI_REVISION_SHA1
ENV UCLAPI_REVISION_SHA1 ${UCLAPI_REVISION_SHA1}

ARG ENVIRONMENT
ENV ENVIRONMENT ${ENVIRONMENT}

#################################
########### Let's go! ###########
#################################
RUN mkdir /web && \
    mkdir -p /opt/oracle
WORKDIR /web

COPY non-public/${ENVIRONMENT}/uclapi/uclfw.rules /web/uclfw.rules

RUN apt-get update && \
    apt-get install -y python3 \
                       python3-pip \
                       libaio1 \
                       wget \
                       git \
                       libpq-dev \
                       libpq5 \
                       libpython3-dev \
                       unzip \
                       build-essential \
                       libpcre3 \
                       libpcre3-dev \
                       sed \
                       supervisor \
                       liblz4-1 &&\
    apt-get clean

# Install Oracle. This does the following:
# - Downloads and unzips the instant client
# - Downloads and unzips the instant client SDK
# - Symlinks the required library files
# - Updates the symbol cache
# - Installs the ORACLE_HOME into the system environment variables
# - Sets up ld so that future lookups for .so files will be resolvable using the Oracle directory
RUN wget -O instantclient.zip ${ORACLE_INSTANTCLIENT_BASIC_URL} && \
    unzip -d/opt/oracle instantclient.zip && \
    wget -O instantclientsdk.zip ${ORACLE_INSTANTCLIENT_SDK_URL} && \
    unzip -d/opt/oracle instantclientsdk.zip && \
    rm instantclient.zip && \
    rm instantclientsdk.zip && \
    ln -s ${ORACLE_HOME}/libclntsh.so.$ORACLE_SO_VERSION ${ORACLE_HOME}/libclntsh.so && \
    ln -s ${ORACLE_HOME}/libocci.so.$ORACLE_SO_VERSION ${ORACLE_HOME}/libocci.so && \
    ln -s ${ORACLE_HOME}/libclntshcore.so.$ORACLE_SO_VERSION ${ORACLE_HOME}/libclntshcore.so && \
    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${ORACLE_HOME} && \
    ldconfig && \
    grep -q -F "ORACLE_HOME=${ORACLE_HOME}" /etc/environment || echo "ORACLE_HOME=${ORACLE_HOME}" >> /etc/environment && \
    echo "${ORACLE_HOME}" > /etc/ld.so.conf.d/oracle.conf && \
    ldconfig

# Put the UCL firewall rules into the hosts file
RUN cat /web/uclfw.rules >> /etc/hosts && \
    rm /web/uclfw.rules

# Install the Supervisor configuration files
COPY ./uclapi/supervisor-conf/supervisord.conf      /etc/supervisor/supervisord.conf
COPY ./uclapi/supervisor-conf/gunicorn-django.conf  /etc/supervisor/conf.d/
COPY ./uclapi/supervisor-conf/celery-uclapi.conf    /etc/supervisor/conf.d/

# Invalidate the build cache using the GitHub API if there has been a new commit.
# Courtesy of https://stackoverflow.com/a/39278224
ADD https://api.github.com/repos/uclapi/uclapi/git/refs/heads/${UCLAPI_BRANCH} version.json

# Install the run script
COPY ./uclapi/run.sh /web/run.sh
RUN chmod +x /web/run.sh

# Install the UCL API
RUN git clone ${UCLAPI_GIT_ADDRESS} -b ${UCLAPI_BRANCH}

WORKDIR /web/uclapi

# If a revision other than the latest has been requested, check that revision out.
# Otherwise, we'll stick to master.
RUN if [ "${UCLAPI_REVISION_SHA1}" != "latest" ]; then git reset --hard ${UCLAPI_REVISION_SHA1}; fi

RUN pip3 install -r backend/uclapi/requirements.txt && \
    pip3 install gunicorn

COPY non-public/${ENVIRONMENT}/uclapi/uclapi.env /web/uclapi/backend/uclapi/.env

# Ensure Supervisor works. If we get an error here then we know something is wrong.
# If Supervisor restarts successfully and all services start then we are okay.
RUN service supervisor stop; \
    service supervisor start; \
    supervisorctl restart all

# Gunicorn runs on Port 9000
EXPOSE 9000

CMD /web/run.sh
