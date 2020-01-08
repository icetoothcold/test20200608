*********
Try sriov
*********

1. bash set_sriov.sh <网卡1> <网卡2>，成功执行后，需要reboot

2. 测试sriov VF可用性

::

    ip l add link cbond0 name cbond0.0 type vlan id <VLAN-ID>
    ip netns add test
    ip l set cbond0.0 netns test
    ip netns exec ip l set cbond0.0 up
    ip netns exec ip a add dev cbond0.0 <IP>/<MASK>
    ip netns exec ip r add default via <GATEWAY>
    ip netns exec ping ...

3. cni二进制文件:

  - /opt/cni/bin/sriovMGR, chmod +x
  - /opt/cni/bin/sriov-cni, chmod +x

4. cni env:

::

    # cat /etc/cni/net.d/10-default.conf
    {
        "cniVersion": "0.2.0",
        "name": "mynet",
        "type": "sriov-cni",
        "shellDir": "/opt/cni/bin",
        "noCheckVolumePath": false,
        "master": "https://<MASTER_IP>:6443",
        "kubeConfig": "/etc/kubernetes/kubelet.conf"
    }

5. yum install jq -y

6. edit operator.yaml

::

    + tolerations:
    + - effect: NoExecute
    +   operator: Exists
    + - effect: NoSchedule
    +   operator: Exists
