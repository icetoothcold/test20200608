*********************
Calico ippool usages
*********************

(我们当前用的是calico v3.7.3，可能需要升级到v3.10)

calicoctl.sh
============

kubespray在部署后，会在master节点生成一个脚本calicoctl.sh，通过这个脚本可以方便的使用calicoctl。这个脚本指定了ETCD_ENDPOINT, ETCD_CA_CERT_FILE等calicoctl需要的参数和文件。

ippool
======

Refer: https://docs.projectcalico.org/v3.7/reference/calicoctl/resources/ippool

ippool 顾名思义就是ip池，calico为Pod配置的IP来自这个池子。在 https://docs.projectcalico.org/v3.7/reference/cni-plugin/configuration#ipam 中，介绍到，默认地，calico会从所有可用的ippool里为Pod分配IP，但如果显示地指定了ipv4_pools，那么默认就只会从指定的池子里分配IP。

(https://docs.projectcalico.org/v3.7/reference/cni-plugin/configuration 显示了更多的容器网络布局的可能性，如:

  - Container settings
    设置allow_ip_forwarding为true则允许Pod内允许转发，如果想利用Pod做一个路由器，需要这样配置。

  - Using host-local IPAM
    由k8s node的podCIDR来提供各个分散的地址池。一种场景是，集群跨AZ部署，网管为集群预留了Pod IP段，但不同AZ有不同分段的IP池。如果我们由calico来分配各个节点的子网段，那么可能Pod IP无法满足各个AZ中的网络规划，无法通信。但如果使用各个node的podCIDR，则可以在预先知道node的物理拓扑的情况下，指定合理的Pod IP段。

  - Specifying IP pools on a per-namespace or per-pod basis
    给Pod指定IP没什么好说的，比较有意思的是给一个namespace指定IP池。如果还是overlay，纯虚IP并没有什么实际意义，但如果这些IP段是由网管规划预留给集群使用的，那么就会在集群与传统网络中产生联动。

  - Requesting a floating IP
    在v3.7.3中没有实验出来。浮动的IP是在来IaaS的东西，目前我想不到在容器上面有什么意义。

  - Using IP pools node selectors
    和前面的Using host-local IPAM有相似的使用场景，目的都是assigning IP addresses based on topology，但不同的是，host-local必然要求不同的node在不同的子网段，但是node selectors则允许了几个node在同一个子网段下。

)


沉降为underlay网络
------------------

前提是已经与网管协商，规划预留好了给集群用的地址段。之后可以在集群创建时，在kubespray/roles/network_plugin/calico/defaults/main.yml 中设置nat_outgoing为false。如果集群已经创建完，参考 https://docs.projectcalico.org/v3.7/networking/changing-ip-pools 。

集群方面需要将ippool的natOutgoing调整为false，其次各个计算节点需要调整sysctl net.ipv4.conf.<业务网口>.proxy_arp=1，即开启arp代答。此外，为了提高性能，可以选择性的将ipipMode和vxlanMode都设置为Never，即不用隧道封装，参考https://docs.projectcalico.org/v3.7/networking/vxlan-ipip。

上游网络方面，除了网管需要预留地址段外，还需要配置交换设备。需要为各个节点上的子网段添加路由，是的集群内的“半虚”IP，能够被外部所识别。上面提到的开启arp代答是为了解决接入交换机不能配置路由的场景。


多地址池支持
------------

对于某些场景，整个集群直接沉降到underlay可能并不适用，这时候我们可以创建多个地址池，配置calico ipv4_pools 只使用虚IP地址池。之后针对有需要的namespace或者pod，使用“Specifying IP pools on a per-namespace or per-pod basis”方法配置IP。


结合跨AZ
---------

在沉降到underlay后，比较好的方式是使用node selectors。
