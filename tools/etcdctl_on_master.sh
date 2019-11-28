#!/bin/bash
ETCD1_IP=""
ETCD2_IP=""
ETCD3_IP=""
ETCDCTL_API=3 \
ETCDCTL_ENDPOINTS=https://$ETCD1_IP:2379,https://$ETCD2_IP:2379,https://$ETCD3_IP:2379 \
ETCDCTL_CACERT=/etc/ssl/etcd/ssl/ca.pem \
ETCDCTL_CERT=/etc/ssl/etcd/ssl/member-`hostname`.pem \
ETCDCTL_KEY=/etc/ssl/etcd/ssl/member-`hostname`-key.pem \
/usr/local/bin/etcdctl "$@"
