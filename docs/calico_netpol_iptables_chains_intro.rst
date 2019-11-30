************************************
Calico netpol iptables chains 简要说明
************************************


netpol
======

default-all-egress-all::

    spec:
      egress:
      - to:
        - podSelector: {}
        - namespaceSelector: {}
        - ipBlock:
            cidr: 169.254.25.10/32
      podSelector: {}
      policyTypes:
      - Egress

default-all-ingress-deny::

    spec:
      ingress:
      - from:
        - podSelector: {}
        - namespaceSelector:
            matchLabels:
              name: kube-system
        - ipBlock:
            cidr: 169.254.25.10/32
        - ipBlock:
            cidr: 10.233.90.0/32
      podSelector: {}
      policyTypes:
      - Ingress


快速定位到iptables
==================

1. 获取interface::

    ip r get POD_IP | awk '/dev/{print $3}'  # on node hosts pod

2. 找到与interface相关的规则::

    iptables -S | grep INTERFACE


简单说明
========

展示的链都会略过了不必要的comments。

1. 出入口检查与分流
-------------------

::

    -A cali-from-wl-dispatch-f -i califb036a61ec6 -m comment --comment "cali:IuYWjHAI1hbD8sd5" -g cali-fw-califb036a61ec6
    -A cali-to-wl-dispatch-f -o califb036a61ec6 -m comment --comment "cali:gGoPnvkExpVZWgVO" -g cali-tw-califb036a61ec6

  上面两个链的前置链会做出入口分流：如果是`-o cali+`(即包从以cali开头的device/interface流出当前主机网络空间的)则进入to whitelist dispatch filter;而如果是`-i cali+`(即包从以cali开头的device/interface流入到当前主机网络空间的)则进入from whitelist dispatch filter。

  上面这两个链针对出口和入口再做一次分拣，将数据包导入特定的链去处理。

2. 白名单"框架"
---------------

::

    1. -A cali-xw-califb036a61ec6 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    2. -A cali-xw-califb036a61ec6 -m conntrack --ctstate INVALID -j DROP
    3. -A cali-xw-califb036a61ec6 -j MARK --set-xmark 0x0/0x10000
    4. -A cali-xw-califb036a61ec6 -m comment --comment "Start of policies" -j MARK --set-xmark 0x0/0x20000
      (policy out from interface/pod)
    5a -A cali-fw-califb036a61ec6 -m mark --mark 0x0/0x20000 -j cali-po-_UUnU9wQK8x0zFhDGHfB
      (policy in to interface/pod)
    5b -A cali-tw-califb036a61ec6 -m mark --mark 0x0/0x20000 -j cali-pi-_R4D4hifwxclBVWqiGad
    6. -A cali-xw-califb036a61ec6 -m comment --comment "Return if policy accepted" -m mark --mark 0x10000/0x10000 -j RETURN
    7. -A cali-xw-califb036a61ec6 -m comment --comment "Drop if no policies passed packet" -m mark --mark 0x0/0x20000 -j DROP
    -A cali-xw-califb036a61ec6 -j cali-pro-kns.XXX
    -A cali-xw-califb036a61ec6 -m comment --comment "Return if profile accepted" -m mark --mark 0x10000/0x10000 -j RETURN
    -A cali-xw-califb036a61ec6 -j cali-pro-_XXX
    -A cali-xw-califb036a61ec6 -m comment --comment "Return if profile accepted" -m mark --mark 0x10000/0x10000 -j RETURN
    -A cali-xw-califb036a61ec6 -m comment --comment "Drop if no profiles matched" -j DROP

xw 指代fw或者tw。除了被标记序号的，其他的链与calico的profile资源对象有关，这里略过。并且上述链略过了不必要的comments。

各条说明:

  1. 是利用了conntrack记录，即只要这包是属于一个ESTABLISHED链路的，或者RELATED到一个已知链路的(例如主进程listen，子进程和客户端建立链接，那就是RELATED)，那么就放行。
  2. 如果所属于的链路的状态是无效的(例如场景tcp挥手后又收到数据包)，则直接丢弃。
  3. 在"通过"标记位上标记0，表示默认不通过。
  4. 标记"policy处理"的标记位。
  5. 进入policy处理的链。这里针对from/to whitelist会走两条不同的链，对应policy out/in。
  6. 匹配"通过"标记位，如果是1，则放行。
  7. 如果数据包有"policy处理"标记位，但是还没有返回，说明没有被白名单策略匹配到，就默认drop了。

3. policy out
-------------

::

    -A cali-po-_UUnU9wQK8x0zFhDGHfB -m set --match-set cali40s:w2hnQkgRnY1tzkBk1tBfVIC dst -j MARK --set-xmark 0x10000/0x10000
    -A cali-po-_UUnU9wQK8x0zFhDGHfB -m mark --mark 0x10000/0x10000 -j RETURN
    -A cali-po-_UUnU9wQK8x0zFhDGHfB -m set --match-set cali40s:w2hnQkgRnY1tzkBk1tBfVIC dst -j MARK --set-xmark 0x10000/0x10000
    -A cali-po-_UUnU9wQK8x0zFhDGHfB -m mark --mark 0x10000/0x10000 -j RETURN
    -A cali-po-_UUnU9wQK8x0zFhDGHfB -m set --match-set cali40s:d0vaXDV0OjdKq6czssWe9SI dst -j MARK --set-xmark 0x10000/0x10000
    -A cali-po-_UUnU9wQK8x0zFhDGHfB -m mark --mark 0x10000/0x10000 -j RETURN

cali40s:w2hnQkgRnY1tzkBk1tBfVIC 和 cali40s:d0vaXDV0OjdKq6czssWe9SI 对应当前namespace和kube-system的ipset，可以用命令`ipset list cali40s:d0vaXDV0OjdKq6czssWe9SI`查看。目前尚不清楚为什么当前namespace会被匹配两次。

如果数据包的目标地址能够在ipset中匹配到，将"通过"标记未置为1，然后返回。

4. policy in
------------

::

    -A cali-pi-_R4D4hifwxclBVWqiGad -m set --match-set cali40s:w2hnQkgRnY1tzkBk1tBfVIC src -j MARK --set-xmark 0x10000/0x10000
    -A cali-pi-_R4D4hifwxclBVWqiGad -m mark --mark 0x10000/0x10000 -j RETURN
    -A cali-pi-_R4D4hifwxclBVWqiGad -m set --match-set cali40s:w2hnQkgRnY1tzkBk1tBfVIC src -j MARK --set-xmark 0x10000/0x10000
    -A cali-pi-_R4D4hifwxclBVWqiGad -m mark --mark 0x10000/0x10000 -j RETURN
    -A cali-pi-_R4D4hifwxclBVWqiGad -m set --match-set cali40s:d0vaXDV0OjdKq6czssWe9SI src -j MARK --set-xmark 0x10000/0x10000
    -A cali-pi-_R4D4hifwxclBVWqiGad -m mark --mark 0x10000/0x10000 -j RETURN
    -A cali-pi-_R4D4hifwxclBVWqiGad -s 10.233.90.0/32 -j MARK --set-xmark 0x10000/0x10000
    -A cali-pi-_R4D4hifwxclBVWqiGad -m mark --mark 0x10000/0x10000 -j RETURN

如果:

  1. 数据包的源地址能够在ipset中匹配到;
  2. 源IP能匹配到指定IP;

则将"通过"标记未置为1，然后返回。
