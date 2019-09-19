# Changelog

oneCacheKS致力于快速构建稳定可用的Kubernetes集群及其生态。



## 0.3.0 (2019-09-19)

为上层获取kubernetes API token提供了更便捷的方式。

### Features

* loginapp-proxy: 更便捷的通过API获取k8s API token



## 0.2.0 (2019-09-12)

提供了比较完整的Kubernetes集群及部分组件安装方式

### Features
  
* 增加基础架构组件的部署脚本，包括:
  - onecache
  - harbor
  - chartmuseum
  - ldap
* 增加kubernetes集群部署预安装脚本，包括从部署节点到k8s集群节点的免密授信，基础架构组件的域名解析等功能
* 优化kubernetes集群部署清单的编排
* 增加k8s集群部署后的插件安装集成脚本，包括:
  - dex
  - loginapp
  - keepalived
  - ingress



## 0.1.0 (2019-09-05)

第一次release

### Documents

选型:
  - 从开源社区选取了kubespray作为集群的部署工具
  - 选择calico作为网络插件，因为它兼具性能和对NetworkPolicy的支持
  - 选择harbor作为镜像仓库，因为它在与ldap集成，备份，垃圾清理方面做的比较成熟。基于对我们平台场景的理解，目前暂不考虑dragonfly等具备P2P分发能力的镜像仓库项目
  - 选择chartmuseum作为现阶段的集群helm仓库，为集群的集成插件的部署，以及平台的编排部署提供支撑
  - 使用自研的onecache组件，为集群的私有yum仓库和文件下载服务器提供支撑
  - 选择coredns，因为它具有丰富的插件，例如hosts, etcd等对于集群管理和功能支持上比较有利
  - 选择dex以及loginapp作为k8s与ldap的认证插件，部署简单且易于管理，配置方面满足基本的认证需求


工作流:
  - 收集了基本的k8s集群搭建需要的所有rpm包，二进制文件，容器镜像，分别有onecache和harbor管理和提供给集群节点进行安装部署
  - 跑通了kubespray的集群部署功能，计算节点扩容功能，集群销毁功能
  - 调试了coredns，修改了相关配置参数，已满足简化在域名解析方面集群管理的工作
  - 调试了ldap与k8s/dex和harbor的集成适配:
    - 验证了通过存储在ldap中的用户信息登录harbor
    - 验证了通过存储在ldap中的用户信息获取token来访问k8s API
  - 调试了chartmuseum以及helm，使得相关组件在k8s集群搭建完毕后可以通过helm来安装部署和版本管理控制

