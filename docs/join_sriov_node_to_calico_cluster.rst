*********************************
Join sriov node in calico cluster
*********************************

背景
====

参考scale_node_manually.rst，已将节点加入集群，但未配置cni。

具体步骤
========

准备
----

1. 给calico cni的节点打标签:

::

    kubectl label node <NODE> cni=calico

2. 修改calico-node ds:

::

    kubectl edit ds calico-node
      ...
      updateStrategy:
      - rollingUpdate:
      -   maxUnavailable: n%
      - type: RollingUpdate
      + type: OnDelete

3. 计算节点逐个关调度，删除节点上的calico-node pod

::

    kubectl cordon nodeX
    kubectl delete pod $(kubectl get pod -l k8s-app=calico-node -o wide | awk '/nodeX/{print $1}')
    kubectl get pod --field-selector=spec.nodeName=nodeX -l k8s-app=calico-node -w
    kubectl uncordon nodeX

4. 修改logging namespace下的fluent-bit ds，确认更新策略为OnDelete，然后将新网络插件节点的fluent-bit pod删掉

::

    kubectl -n logging edit ds fluent-bit
        ...
        dnsPolicy: ClusterFirst
    +   hostNetwork: true
        restartPolicy: Always
        ...
      updateStrategy:
    +   type: OnDelete

    kubectl -n logging delete pod fluent-bit-XX
