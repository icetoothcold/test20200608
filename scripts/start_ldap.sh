rootPath="$(cd `dirname $0`; cd ..; pwd)"
source $rootPath/scripts/utils.sh

dataPath=$rootPath/ldap_data/data
configPath=$rootPath/ldap_data/config

if [[ ! -d $dataPath ]]; then
    mkdir -p $dataPath
fi
if [[ ! -d $configPath ]]; then
    mkdir -p $configPath
fi

docker rm -f ldap
docker run --name ldap -d \
  -p 389:389 \
  --env LDAP_ORGANISATION=$ldapOrgName \
  --env LDAP_DOMAIN=$ldapDomain \
  --env LDAP_ADMIN_PASSWORD=$ldapRootPW \
  -v $configPath:/etc/ldap/slapd.d \
  -v $dataPath:/var/lib/ldap \
  $imgRepo/osixia/openldap:1.2.4
