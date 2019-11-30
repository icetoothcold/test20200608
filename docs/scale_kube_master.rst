******************
Scale kube masters
******************

背景
====

默认已将外部etcd（非kubeadm安装）高可用化。
一下内容为如何将节点加入master集群（加入已有集群控制面）。

核心步骤
========

1. master1 kubeadm init为api-server生成新证书
2. kubespray 添加节点到集群 （scale.yml）
3. kubeadm join 到control plane
4. 拷贝ssl, tokens, users等必须文件到新master节点


具体步骤
========

准备
----

1. 备份所有节点的/etc/kubernetes，包括当前所有的masters和nodes
::

    cp -rp /etc/kubernetes /path/to/backup.

2. 修改目标master节点的docker配置:

  - 确认配置--exec-opt native.cgroupdriver=systemd
  - 确认配置--insecure-registry指向私有仓库

3. 确认目标节点的hosts配置，具有私有仓库解析

实施
----

在master1上进行操作

  1. 修改kubeadm-config.yaml

    - apiServer.certSANs,增加新的节点hostname, FQDN, IP
    - etcd.external.endpoints,确认新的etcd节点被添加

  2. 删除apiserver相关证书:
  ::

      rm -f /etc/kubernetes/ssl/apiserver*

  3. 重新生成apiserver相关证书
  ::

      kubeadm init phase certs apiserver --config=kubeadm-config.yaml -v 1
      kubeadm init phase certs apiserver-kubelet-client --config=kubeadm-config.yaml -v 1

在infra上执行

  1. 检测hosts.yaml是否正确
  2. 备份scale.yml
  3. 修改scale.yml

     - 注释掉task "Generate the etcd certificates beforehand"
     - 注释掉task "Target only workers to get kubelet installed and checking in on any new nodes" 中docker部分

  4. 执行ansible
  ::

      ansible-playbook -i inventory/<CLUSTER>/hosts.yml scale.yml -b --private-key=~/.ssh/id_rsa -l NEW_MASTERS

在new masters上执行

  1. 检查/etc/kubernetes下，删除manifests，ssl, kubelet.conf, bootstrap-kubelet.conf
  2. 检查并删除/etc/ssl/dex

在master1上执行

  1. 拷贝证书和必要文件
  ::

    cd /etc/kubernetes/
    scp -rp ssl users tokens root@node2:/etc/kubernetes/
    scp -p /usr/local/bin/kubectl root@node2:/usr/local/bin/
    scp -rp /etc/ssl/dex root@node2:/etc/ssl/

  2. 生成join command
  ::

    kubeadm token create --print-join-command

在new master上执行

  1. 执行join command + 追加参数--control-plane -v1
  2. 根据命令结果，添加.kube/config等

  3. 检查并修改*.conf中的ip为本机ip
  ::

    cd /etc/kubernetes
    grep -nir 'https://IP:6443' .
    sed -i 's#server: https://<OLD-IP>:6443#server: https://<NEW-IP>:6443#g' *.conf

  4. 确认并修改manifests/kube-apiserver.yaml中etcd包含etcd clusters中的多个IP
  5. 修改.kube/config中的IP
  6. 重启kubelet并systemctl enable
