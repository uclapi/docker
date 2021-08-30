#!/bin/bash

# Certbot env setup
if [ ${ENVIRONMENT} = "prod" ]; then
    certbot_hostname="uclapi.com"
else
    certbot_hostname="staging.ninja"
fi

if [ ${DRYRUN} = "1" ]; then
    letsencrypt_url="https://acme-staging-v02.api.letsencrypt.org/directory"
else
    letsencrypt_url="https://acme-v02.api.letsencrypt.org/directory"
fi

while /bin/true; do
    # Certbot setup modified from docker-nginx-certbot
    # https://github.com/JonasAlfredsson/docker-nginx-certbot/blob/b119b10640c1a19bbba7a40fd13ab4e14d801ee5/src/scripts/run_certbot.sh#L52-L66
    # Certbot will write certificates to/etc/letsencrypt/live/uclapi-rsa/
    # See nginx.conf for the actual use of the certificates
    certbot certonly --agree-tos --keep --noninteractive \
        --authenticator webroot --webroot-path=/var/www/letsencrypt \
        --preferred-challenges http-01 \
        --email "isd.apiteam@ucl.ac.uk" \
        --server "${letsencrypt_url}" \
        --key-type "rsa" \
        --cert-name "uclapi-rsa" \
        --domains ${certbot_hostname}

    # Ensure Supervisor is alive first
    ps aux | grep supervisor | grep -q -v grep
    SUPERVISOR_STATUS=$?
    if [ $SUPERVISOR_STATUS -ne 0 ]; then
        service supervisor start
    fi

    # Ensure Shibboleth is running
    service shibd status
    SHIBD_STATUS=$?
    if [ $SHIBD_STATUS -ne 0 ]; then
        service shibd start
    fi

    # Now check each other service
    ps aux | grep shibauthorizer | grep -q -v grep
    SHIBAUTHORIZER_STATUS=$?
    ps aux | grep shibresponder | grep -q -v grep
    SHIBRESPONDER_STATUS=$?
    ps aux | grep nginx | grep -q -v grep
    NGINX_STATUS=$?

    if [ $SHIBAUTHORIZER_STATUS -ne 0 ]; then
        echo "Shibboleth Authorizer exited"
        supervisorctl restart shibauthorizer
    fi
    if [ $SHIBRESPONDER_STATUS -ne 0 ]; then
        echo "Shibboleth Responder exited"
        supervisorctl restart shibresponder
    fi
    if [ $NGINX_STATUS -ne 0 ]; then
        echo "Nginx exited"
        supervisorctl restart nginx
    fi

    sleep 60
done
