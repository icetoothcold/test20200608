docker rm -f ldap
docker run --name ldap -d \
  -v /home/zongkai/workspace/oneCache_kubespray/ldap_data/config:/config \
  -v /home/zongkai/workspace/oneCache_kubespray/ldap_data/data:/data \
  -p 389:389 -e CONF_ROOTPW=ldapAdmin -e CONF_BASEDN=dc=example,dc=com beli/ldap
