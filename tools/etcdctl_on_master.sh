#!/bin/bash
ETCDCTL_API=3 \
ETCDCTL_ENDPOINTS=https://`ip r get 8.8.8.8 | awk '{if(NR=1)print $7}'`:2379 \
ETCDCTL_CACERT=/etc/ssl/etcd/ssl/ca.pem \
ETCDCTL_CERT=/etc/ssl/etcd/ssl/member-`hostname`.pem \
ETCDCTL_KEY=/etc/ssl/etcd/ssl/member-`hostname`-key.pem \
/usr/local/bin/etcdctl "$@"
