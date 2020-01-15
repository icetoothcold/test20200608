*********
Sriov-cni
*********

1. bash set_sriov.sh <网卡1> <网卡2>，成功执行后，需要reboot。
注意: 由于当前方案下，一台计算节点所负载的容器数不大于63个，并且网络方案仅使用单网卡方案，因此由两个计算节点网卡提供bond即可。

2. 测试sriov VF可用性

::

	ip l add link cbond0 name cbond0.0 type vlan id <VLAN-ID>
	ip netns add test
	ip l set cbond0.0 netns test
	ip netns exec ip l set cbond0.0 up
	ip netns exec ip a add dev cbond0.0 <IP>/<MASK>
	ip netns exec ip r add default via <GATEWAY>
	ip netns exec ping ...

3. 将cni二进制文件拷贝到对应路径下，并且修改可执行权限:

  - /opt/cni/bin/sriovMGR, chmod +x
  - /opt/cni/bin/sriov-cni, chmod +x

4. 编辑cni env文件:

::

    # cat /etc/cni/net.d/10-default.conf
    {
        "cniVersion": "0.2.0",
        "name": "mynet",
        "type": "sriov-cni",
        "shellDir": "/opt/cni/bin",
        "noCheckVolumePath": false,
        "master": "https://localhost:6443",
        "kubeConfig": "/etc/kubernetes/kubelet.conf",
        "totoalvfs": 63
    }

5. 安装依赖:

::

	yum install jq -y

6. edit operator.yaml

::

	+ tolerations:
	+ - effect: NoExecute
	+   operator: Exists
	+ - effect: NoSchedule
	+   operator: Exists

7. 编辑/etc/rc.d/rc.local文件，并检查rc.local文件具有可执行权限。说明:

  - 新版的自研sriov-cni插件使用的节点本地的网卡分配注册机制，会在/var/run/sriov目录下文件
  - 文件名格式为: <cbondN>-<namespaceName>.<podName>，如cbond1-kube-system.busybox1，即说明当前节点上的cbond1分配给了kube-system命名空间下的busybox1 pod
  - 文件内容为网卡分配的引用数，通常为1，表示网卡只被一个Pod使用。特殊情况为2，例如同一命名空间下的一个Pod在被delete --force --grace-period=0删除后，新的同名Pod再次被调度到同一节点后，文件内容会短暂的变为2，但之后会恢复为1。
  - 针对节点重启的场景，由于Pod是否还会调度到重启节点的情况无法得知，因此需要再节点重启后，清除之前的网卡分配记录，让Pod重新在节点上重新分配网卡，因此需求删除/var/run/sriov目录后再重建。

::

	systemctl stop kubelet
	rm -rf /var/run/sriov && mkdir /var/run/sriov && chown kube /var/run/sriov
	systemctl start kubelet
