#!/bin/bash
couchusername=$1
couchpassword=$2

docker stop identity.integration.couchdb
docker rm identity.integration.couchdb
docker volume rm identity-int-db-data
docker run -d --name identity.integration.couchdb -p 5984:5984 -e COUCHDB_USER=$couchusername -e COUCHDB_PASSWORD=$couchpassword -v identity-int-db-data://opt/couch/data healthcatalyst/fabric.docker.couchdb

docker stop identity.integration.openldap
docker rm identity.integration.openldap
docker run -d --name identity.integration.openldap -d -p 389:389 -e LDAP_ADMIN_PASSWORD=password healthcatalyst/fabric.docker.openldap
export COUCHDBSETTINGS__USERNAME=$couchusername
export COUCHDBSETTINGS__PASSWORD=$couchpassword

sleep 3

dotnet test ../../Fabric.Identity.IntegrationTests/Fabric.Identity.IntegrationTests.csproj

docker stop identity.integration.couchdb
docker rm identity.integration.couchdb 
docker volume rm identity-int-db-data
docker stop identity.integration.openldap 
docker rm identity.integration.openldap