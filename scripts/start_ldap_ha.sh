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

ips=`get_infra_ips "${ldapHosts[@]}"`
hostname=""
hostnameIdx=1
hosts=""
hostAddn=""
for ip in ${ips[@]}; do
    if [[ `ip a | grep -c $ip` -eq 1 ]]; then
        hostname=ldap$hostnameIdx.$ldapDomain
    fi
    hosts="'ldap://ldap$hostnameIdx.$ldapDomain',${hosts[@]}"
    hostAddn="--add-host ldap$hostnameIdx.$ldapDomain:$ip ${hostAddn[@]}"
    hostnameIdx=$((hostnameIdx+1))
done
hosts=${hosts:0:-1}

if [[ -z $hostname ]]; then
    echo "failed to determine hostname"
    exit
fi

docker rm -f ldap
docker run --name ldap -d --hostname $hostname --env LDAP_REPLICATION=true \
  -p 389:389 \
  --env LDAP_ORGANISATION=$ldapOrgName \
  --env LDAP_DOMAIN=$ldapDomain \
  --env LDAP_ADMIN_PASSWORD=$ldapRootPW \
  --env LDAP_REPLICATION=true \
  --env LDAP_REPLICATION_HOSTS="#PYTHON2BASH:[$hosts]" \
  $hostAddn \
  -v $configPath:/etc/ldap/slapd.d \
  -v $dataPath:/var/lib/ldap \
  --restart 'always' \
  $imgRepo/osixia/openldap:1.2.4
