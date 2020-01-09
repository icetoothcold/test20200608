***************
Add calico-node
***************

依赖:

  - 参考scale_node_manually.rst，添加完节点，kubectl get node 观察到节点为NotReady
  - master1上的/etc/ssl/etcd/openssl.conf
  - master1上的/etc/ssl/etcd/ss/ca.pem
  - master1上的/etc/ssl/etcd/ss/ca-key.pem

1. cordon:

::

    kubectl cordon <NEW-NODE>

2. 在master1上 使用脚本 tools/gen_node_etcd_certs.sh 为新节点的calico-node生成etcd证书:

::

    bash tools/gen_node_etcd_certs.sh <NEW-NODE-HOSTNAME>

3. 将新生成的证书以及etcd ca.pem拷贝的新节点的/etc/calico/certs目录下:

  - node-<NEW-NODE-HOSTNAME>.pem
  - node-<NEW-NODE-HOSTNAME>-key.pem
  - /etc/ssl/etcd/ssl/ca.pem

4. 在新节点上:

::

    cd /etc/calico/certs
    mv node-<NEW-NODE-HOSTNAME>.pem cert.crt
    mv node-<NEW-NODE-HOSTNAME>-key.pem key.pem
    mv ca.pem ca_cert.crt

5. 删除新节点上的calico-node pod，让daemonSet重新创建pod
