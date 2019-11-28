mkdir -p /etc/yum.repos.d/bak
mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/

echo "192.168.122.239 local.repo.io" >> /etc/hosts
curl -o /etc/yum.repos.d/private.repo http://local.repo.io:8080/private.repo

systemctl stop firewalld
systemctl disable firewalld
yum clean all
yum install -y docker-ce

echo "192.168.122.239 local.harbor.io" >> /etc/hosts
sed -i "/ExecStart=/ s/$/ --insecure-registry=local.harbor.io/" /usr/lib/systemd/system/docker.service
systemctl daemon-reload
systemctl start docker
systemctl enable docker

echo "# Environment file for etcd v3.3.10
ETCD_DATA_DIR=/var/lib/etcd
ETCD_ADVERTISE_CLIENT_URLS=https://192.168.122.66:2379
ETCD_INITIAL_ADVERTISE_PEER_URLS=https://192.168.122.66:2380
ETCD_INITIAL_CLUSTER_STATE=existing
ETCD_METRICS=basic
ETCD_LISTEN_CLIENT_URLS=https://192.168.122.66:2379,https://127.0.0.1:2379
ETCD_ELECTION_TIMEOUT=5000
ETCD_HEARTBEAT_INTERVAL=250
ETCD_INITIAL_CLUSTER_TOKEN=k8s_etcd
ETCD_LISTEN_PEER_URLS=https://192.168.122.66:2380
ETCD_NAME=etcd3
ETCD_PROXY=off
ETCD_INITIAL_CLUSTER=etcd1=https://192.168.122.57:2380,etcd2=https://192.168.122.62:2380,etcd3=https://192.168.122.66:2380
ETCD_AUTO_COMPACTION_RETENTION=8
ETCD_SNAPSHOT_COUNT=10000

# TLS settings
ETCD_TRUSTED_CA_FILE=/etc/ssl/etcd/ssl/ca.pem
ETCD_CERT_FILE=/etc/ssl/etcd/ssl/member-node3.pem
ETCD_KEY_FILE=/etc/ssl/etcd/ssl/member-node3-key.pem
ETCD_CLIENT_CERT_AUTH=true

ETCD_PEER_TRUSTED_CA_FILE=/etc/ssl/etcd/ssl/ca.pem
ETCD_PEER_CERT_FILE=/etc/ssl/etcd/ssl/member-node3.pem
ETCD_PEER_KEY_FILE=/etc/ssl/etcd/ssl/member-node3-key.pem
ETCD_PEER_CLIENT_CERT_AUTH=True" > /etc/etcd.env

echo '#!/bin/bash
/usr/bin/docker run \
  --restart=on-failure:5 \
  --env-file=/etc/etcd.env \
  --net=host \
  -v /etc/ssl/certs:/etc/ssl/certs:ro \
  -v /etc/ssl/etcd/ssl:/etc/ssl/etcd/ssl:ro \
  -v /var/lib/etcd:/var/lib/etcd:rw \
  --memory=512M \
  --blkio-weight=1000 \
  --name=etcd3 \
  local.harbor.io/coreos/etcd:v3.3.10 \
  /usr/local/bin/etcd \
  "$@"' > /usr/local/bin/etcd

chmod 750 /usr/local/bin/etcd

mkdir -p /etc/ssl/etcd/ssl
