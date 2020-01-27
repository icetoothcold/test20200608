********************
Calico external node
********************

背景
====

公有云环境下，非容器集群的节点上的业务需要与容器集群内的业务互通，这里的互通需要在同一网络平面上。即对于集群外的服务A与集群内的服务B而言，它们认为对方的IP是可以和自己直接通信的，不需要借助NAT。

其次公有云环境下，云服务器即虚机，除了安全组这种显性的端口控制手段外，还有port security这种隐性的控制规则，这种规则主要用于防止IP欺诈，即虚拟机只能使用从云平台那里分配来的IP进行通信，不能随便使用其他IP。

防IP欺诈导致对于overlay网络而言，必须借助隧道，否则会被拦截。


目标
====

在集群外的节点上配置IP-in-IP(简称ipip)隧道，使得集群外的节点能以ipip隧道的方式和集群内的业务pod通信。
以注册中心场景为例，前述的服务A和B都会将服务进程看到的eth0的IP注册到注册中心，以便其他业务以此IP来和自己建立通信。
因此:

  - A访问B时，将以Pod的IP为目的IP发起访问，但请求的源IP将是A的隧道IP；
  - B访问A时，将以A所在虚机的IP发起访问，但请求的源IP将是Pod所在节点的IP。


操作
====

在集群外的节点上
----------------

编辑/etc/rc.d/rc.local，添加如下内容:

::

    modprobe ipip
    sysctl net.ipv4.conf.all.forwarding=1
    sysctl net.ipv4.conf.all.rp_filter=0
    ip l set tunl0 up
    # 为tunl0添加IP，10.233.101.0/32 不在集群已有的子网范围内
    ip a add dev tunl0 10.233.101.0/32
    # 添加到集群其他节点的路由，格式为:
    # <集群子网> via <集群节点IP> dev tunl0 onlink
    ip r add 10.233.90.0/24 via 172.16.0.3 dev tunl0 onlink
    ip r add 10.233.92.0/24 via 172.16.0.11 dev tunl0 onlink
    ip r add 10.233.96.0/24 via 172.16.0.6 dev tunl0 onlink
    ip r add 10.233.97.0/24 via 172.16.0.9 dev tunl0 onlink
    ip r add 10.233.98.0/24 via 172.16.0.2 dev tunl0 onlink
    ip r add 10.233.99.0/24 via 172.16.0.17 dev tunl0 onlink

重启节点。

在master1上
-----------

将集群外的节点添加为calico-node，执行 calicoctl.sh create -f <FILE_CONTENT_AS_BELOW>

::
    apiVersion: projectcalico.org/v3
    kind: Node
    metadata:
      name: <节点hostname>
    spec:
      bgp:
        ipv4Address: <节点IP/32>
        ipv4IPIPTunnelAddr: <节点tunl0 IP>

添加引导路由，只需要master1上添加，集群的其他节点应该可以通过calico-node的bird进程进行BGP同步。

::

    ip r add 10.233.101.0/32 via <节点IP> dev tunl0 onlink
