******************
Scale Etcd Cluster
******************

备份
====

备份，备份，备份！！！ 重要的事说三遍！

etcd数据
::

    # 如果当前只有一个etcd实例，那么ETCDCTL_ENDPOINTS中可以只写一个，但当有多个的时候，最好都写上，不偷懒
    ETCDCTL_API=3 \
    ETCDCTL_ENDPOINTS=https://<IP1>:2379,https://<IP2>:2379,https:/<IP3>:2379 \
    ETCDCTL_CACERT=/path/to/ca.pem \
    ETCDCTL_CERT=/path/to/cert.pem \
    ETCDCTL_KEY=/path/to/key.pem \
    etcdctl snapshot save <FILE_NAME_TO_SAVE>

etcd证书以及openssl.conf
::

    # -p来保持现有的user/group rwx权限等
    cp -rp /etc/ssl/etcd /path/to/backup

（可选)etcd数据目录
::

    cp -rp /var/lib/etcd /path/to/backup

**calico场景**: 备份/etc/calico/certs
::

    cp -rp /etc/calico/certs /path/to/backup

etcd集群检查
============

检查当前member信息
::

    ETCDCTL_API=3 \
    ETCDCTL_ENDPOINTS=https://<IP1>:2379,https://<IP2>:2379,https:/<IP3>:2379 \
    ETCDCTL_CACERT=/path/to/ca.pem \
    ETCDCTL_CERT=/path/to/cert.pem \
    ETCDCTL_KEY=/path/to/key.pem \
    etcdctl member list

如果发现有member用的peer urls是localhost的，则需要修改为节点IP
::

    # <member ID>由命令member list获取
    ETCDCTL_API=3 \
    ETCDCTL_ENDPOINTS=https://<IP1>:2379,https://<IP2>:2379,https:/<IP3>:2379 \
    ETCDCTL_CACERT=/path/to/ca.pem \
    ETCDCTL_CERT=/path/to/cert.pem \
    ETCDCTL_KEY=/path/to/key.pem \
    etcdctl member update <member ID> --peer-urls=https://<IP>:2380


节点准备
========

同步各个节点的/etc/hosts，关闭firewalld
::

    systemctl stop firewalld
    systemctl disable firewalld

新的节点上安装docker-ce
::

    yum install docker-ce
    # docker-ce配置insecure-registry
    systemctl daemon-reload
    systemctl start docker
    systemctl enable docker

将现有etcd实例所在节点的/etc/pki下的CA, ca-trust, tls，以及/usr/local/bin/etcd和/etc/etcd.env同步到新的etcd实例所在节点对应目录下
::

    scp -r /etc/pki/{CA,ca-trust,tls} root@IP:/etc/pki
    scp -r /usr/local/bin/etcd root@IP:/usr/local/bin/etcd
    scp -r /etc/etcd.env root@IP:/etc/etcd.env


在新的节点上创建/etc/ssl/etcd/ssl目录
::

    mkdir -p /etc/ssl/etcd/ssl

生成及分发证书
==============

在现有etcd实例所在节点上，修改/etc/ssl/etcd/openssl.conf文件，为新的etcd实例节点添加DNS和IP记录，例如
::

    ...
    DNS.8 = node2
    DNS.9 = node3
    ...
    IP.4 = 192.168.122.62
    IP.5 = 192.168.122.66

使用命令生成证书
::

   # MASTERS和HOSTS都是必要的，空格作为分隔符
   # MASTERS为所有的etcd实例所在节点的列表
   # HOSTS为所有需要连etcd的节点
   MASTERS="hostname1 hostname2 ..." \
   HOSTS="hostname1 hostname2 ..." \
   /usr/local/bin/etcd-scripts/make-ssl-etcd.sh \
       -f /etc/ssl/etcd/openssl.conf \
       -d /path/to/new/certs


将新生成的所有证书同步到新的etcd实例节点上
::

    scp -r /path/to/new/certs root@IP:/etc/ssl/etcd/ssl/

将新生成的节点相关的证书同步到对应节点上
::

    scp /path/to/new/ca.pem \
        /path/to/new/node-nodeN.pem \
        /path/to/new/node-nodeN-key.pem \
        root@nodeN:/etc/ssl/etcd/ssl/

**calico场景**: 在上一步的基础上，*在运行calicon组件节点上* 更新calico使用的证书
::

    cp /etc/ssl/etcd/ssl/ca.pem /etc/calico/certs/ca_cert.crt
    cp /etc/ssl/etcd/ssl/node-nodeN.pem /etc/calico/certs/cert.crt
    cp /etc/ssl/etcd/ssl/node-nodeN-key.pem /etc/calico/certs/key.pem


使用新的证书启动etcd
====================

在现有的etcd实例节点上，用新的证书替换现有证书
::

    cd /etc/ssl/etcd/ssl
    mkdir old
    mv *.pem old
    cp /path/to/new/certs/*.pem .

在现有的etcd实例节点上，重启etcd实例
::

    # 通过命令`docker ps | grep etcd`查看当前etcd实例命
    docker rm -f etcdN
    # 通过etcd命令(/usr/local/bin/etcd)来启动etcd
    etcd
    # 观察日志正常后，Ctrl-C，然后通过docker再次启动
    docker start etcdN


修复k8s组件
===========

重启kubelet
::

    service restart kubelet

切换到kube-system namespace，**后续的k8s操作都在这个namespace中**
::

    kubectl config set-context --namespace kube-system --current

删除现有kube-apiserver pod，让kubelet再重新创建kube-apiserver pod
::

    kubectl delete pod kube-apiserver-X

删除现有的secret etcd和etcd-ca，并利用新的证书重做
::

    kukbectl delete secret etcd
    kukbectl delete secret etcd-ca
    kubectl create secret tls etcd --cert=/path/to/new/node-MASTER1.pem \
        --key=/path/to/new/node-MASTER1-key.pem
    kubectl create secret generic etcd-ca --from-file=/path/to/new/ca.pem
    
删除现有的calico相关的pod
::

    kubectl delete pod calico-kube-controller-X calico-node-X

删除现有的coredns相关的pod
::

    kubectl delete pod coredns-X

删除现有的kube-proxy相关的pod
::

    kubectl delete pod kube-proxy-X

观察以上pod的重建，确认无误。


填加etcd实例
============

如果有多个新加实例，那么以下操作相关节点上逐个进行。

在新的etcd实例节点上，需改/etc/etcd.env:
    - 修改相关的暴露/listen的IP
    - 修改ETCD_NAME
    - 修改ETCD_INITIAL_CLUSTER，将新实例listen peer urls追加上去。
    - 替换使用的证书

**注意**，后续节点对于修改ETCD_INITIAL_CLUSTER，需要在之前已添加的基础上进行追加。
例如，原有etcd1，现在有新加etcd2和etcd3；那么在处理完etcd2后，在处理etcd3时，ETCD_INITIAL_CLUSTER的值应该为etcd1=..,etcd2=...,etcd3=...。

在新的etcd实例节点上，修改/usr/local/bin/etcd, 修改name字段。

在新的etcd实例节点上，启动etcd实例
::

    # 通过etcd命令(/usr/local/bin/etcd)来启动etcd
    etcd
    # 观察日志，出现"member count is unequal"后，Ctrl-C，然后通过docker再次启动
    docker start etcdN

在现有的etcd实例节点上，通过etcdctl命令添加新的member
::

    ETCDCTL_API=3 \
    ETCDCTL_ENDPOINTS=https://IP1:2379,https://IP2:2379,https://IP3:2379 \
    ETCDCTL_CACERT=/etc/ssl/etcd/ssl/ca.pem \
    ETCDCTL_CERT=/etc/ssl/etcd/ssl/member-`hostname`.pem \
    ETCDCTL_KEY=/etc/ssl/etcd/ssl/member-`hostname`-key.pem \
    /usr/local/bin/etcdctl member add etcdN --peer-urls=https://<IP>:2380

在新的etcd实例节点上，重新启动etcd实例
::

    docker start etcdN

通过etcdctl命令检查member list和endpoint health。
