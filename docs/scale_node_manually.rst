****************
Scale kube nodes
****************

背景
====

为已有集群加入node节点，当前集群的cni为calico。

具体步骤
========

在新安装的节点上执行:

a1. 在新安装的节点上添加新的用户:

::

    echo "kube:x:997:995:Kubernetes user:/home/kube:/sbin/nologin" >> /etc/passwd

a2. 在新安装的节点上创建以下目录，并修改owner:

::

    mkdir -p /etc/kubernetes/{manifests,ssl}
    chown kube /etc/kubernetes
    chown kube /etc/kubernetes/manifests

a3. 配置/etc/hosts:

::

    echo "<HARBOR_IP>  <HARBOR_DOMAIN>" >> /etc/hosts
    echo "<REPO_IP>  <REPO_DOMAIN>" >> /etc/hosts

a4. 配置yum repo:

::

    mkdir -p /etc/yum.repos.d/bak
    mv /etc/yum.repos.d/*repo /etc/yum.repos.d/bak
    curl -o /etc/yum.repos.d/private.repo http://<REPO_DOMAIN>:8080/private.repo

a5. 安装docker-ce，并配置:

::

    yum install docker-ce -y
    vi /usr/lib/systemd/system/docker.service
    (append) --insecure-registry <HARBOR_DOMAIN> --exec-opt native.cgroupdriver=systemd
    systemctl daemon-reload
    systemctl enable docker
    systemctl start docker

a6. 安装socat:

::

    yum install socat -y

a7. 禁用swap:

::

    swapoff -a
    edit /etc/rc.d/rc.local, 添加swapoff -a

a8. 禁用firewalld:

::

    systemctl stop firewalld
    systemctl disable firewalld

a9. 配置sysctl:

::

    echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables
    echo 1 > /proc/sys/net/bridge/bridge-nf-call-ip6tables
    echo 1 > /proc/sys/net/bridge/bridge-nf-call-arptables
    echo 0 > /proc/sys/net/ipv4/tcp_tw_recycle
    echo 0 > /proc/sys/net/ipv4/tcp_tw_reuse
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo "20000   65535" > /proc/sys/net/ipv4/ip_local_port_range
    echo "30000-32767" > /proc/sys/net/ipv4/ip_local_reserved_port

    // really ?
    echo 10 > /proc/sys/vm/swappiness

    echo 1000000 > /proc/sys/fs/inotify/max_user_watches

    echo 1 > /proc/sys/kernel/sysrq

a10. 设置hostname:

::

    hostnamectl set-hostname <NAME>

a11. 更新/etc/hosts，将master和节点自己的fqdn, hostname加入到/etc/hosts

a12. 安装kube-proxy/ipvs依赖:

::

    yum install -y ipvsadm
    modprobe ip_vs
    modprobe ip_vs_rr
    modprobe ip_vs_wrr
    modprobe ip_vs_sh
    modprobe nf_conntrack
    modprobe nf_conntrack_ipv4

a13. 创建nginx目录:

::

	mkdir /etc/nginx
	chmod 700 /etc/nginx

在当前集群的master节点上执行:

b1. 将以下文件scp到新安装的节点的对应路径:

  - /etc/systemd/system/kubelet.service
  - /etc/kubernetes/kubelet.env
  - /etc/kubernetes/kubelet-config.yaml
  - /etc/kubernetes/ssl/ca.crt
  - /etc/kubernetes/ssl/ca.key
  - /usr/local/bin/kubeadm
  - /usr/local/bin/kubelet

b2. 获取join command:

::

    kubeadm token create --print-join-command

b3. !!所有master节点更新/etc/hosts，将新加节点的fqdn, hostname加入到/etc/hosts

在新安装的节点上执行:

c1. 修改kubelet.env:

::

    vi /etc/kubernetes/kubelet.env
    (edit) KUBELET_ADDRESS, KUBELET_HOSTNAME

c2. 修改kubelet-config.yaml:

::

    vi /etc/kubernetes/kubelet-config.yaml
    (edit) address, cgroupDriver

c3. enable并启动kubelet:

::

    systemctl enable kubelet
    systemctl start kubelet
    journalctl -xefu kubelet > unload to load bootstrap kubeconfig: stat /etc/kubernetes/bootstrap-kubelet.conf: no such file or directory

c4. 执行join命令

在master节点上:

d1. get node

::

    kubectl get node

d2. label node

::

    kubectl label node <NEW-NODE> node-role.kubernetes.io/node=""
    kubectl label node <NEW-NODE> alcor.zone=XXX
    kubectl label node <NEW-NODE> cni=XXX

在新装节点上:

e1. 从集群已有计算节点上拷贝以下文件到新装节点对应路径

  - /etc/nginx/nginx.conf
  - /etc/kubernetes/manifests/nginx-proxy.yml

e2. 重启Kubelet

TODO
----

cni

参考:

  - docs/join_sriov_node_to_calico_cluster.rst
  - docs/try_sriov.rst
  - docs/add_calico-node.rst
