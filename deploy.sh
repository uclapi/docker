#!/bin/bash
echo "UCL API Magic Deployment Script"

if [ -z $1 ]
then
    echo "You must pass either prod or staging as an environment variable"
    exit 1
fi

# Combine the base Compose file with an environment-specific Compose file and build
docker-compose -f docker-compose.yml -f docker-compose.$1.yml build

# Then push to the Docker repository listed in the Compose file
docker-compose -f docker-compose.yml -f docker-compose.$1.yml push

# Dump the full configuration out to a temporary compose file
# This is necessary because of https://github.com/moby/moby/issues/29133
docker-compose -f docker-compose.yml -f docker-compose.$1.yml config > docker-compose-tmp.yml

# Deploy the temporary Compose file
docker stack deploy -c docker-compose-tmp.yml --with-registry-auth uclapi

# Delete the temporary Compose file ready for the next run
rm docker-compose-tmp.yml

echo "Hopefully, deployment was successful"
