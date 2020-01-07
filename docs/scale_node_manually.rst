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

a10. 设置hostname:

::

    hostnamectl set-hostname <NAME>

a11. 更新/etc/hosts，将master和节点自己的fqdn, hostname加入到/etc/hosts


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

    vi /etc/kubernetes/kubelet-config.json
    (edit) address, cgroupDriver

c3. enable并启动kubelet:

::

    systemctl enable kubelet
    systemctl start kubelet
    journalctl -xefu kubelet > unload to load bootstrap kubeconfig: stat /etc/kubernetes/bootstrap-kubelet.conf: no such file or directory

c4. 执行join命令

TODO
----

cni
