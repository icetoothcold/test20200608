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

if [[ `ip a | grep -c $myIP` -eq 1 ]]; then
    hostname=ldap1.$ldapDomain
else
    hostname=ldap2.$ldapDomain
fi

docker rm -f ldap
docker run --name ldap -d --hostname $hostname --env LDAP_REPLICATION=true \
  -p $ldapHABackendPort:389 \
  --env LDAP_ORGANISATION=$ldapOrgName \
  --env LDAP_DOMAIN=$ldapDomain \
  --env LDAP_ADMIN_PASSWORD=$ldapRootPW \
  --env LDAP_REPLICATION=true \
  --env LDAP_REPLICATION_HOSTS="#PYTHON2BASH:['ldap://ldap1.$ldapDomain','ldap://ldap2.$ldapDomain']" \
  --add-host ldap1.$ldapDomain:$myIP \
  --add-host ldap2.$ldapDomain:$peerIP \
  -v $configPath:/etc/ldap/slapd.d \
  -v $dataPath:/var/lib/ldap \
  --restart 'always' \
  $imgRepo/osixia/openldap:1.2.4
