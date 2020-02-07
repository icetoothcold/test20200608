******************
infra.yml 参数说明
******************

myIP: 当前infra节点的IP，如果不指定，则通过默认路由进行探测

imageRepo: 镜像仓库的域名

imageRepoSecure: 镜像仓库是否以https方式暴露，目前尚不支持

pkgRepo: 软件仓库/yum源的url

pypiPort: 软件仓库中pypi源暴露的端口，pypi源和yum源公用同一个域名

harborAdminPw: harbor的admin密码

harborGcCron: harbor的垃圾回收周期

harborShareVolume: (废弃)harbor的共享数据存储卷路径

harborWithClair: harbor是否开启clair

harborWithChartmusuem: harbor是否开启chartmuseum

harborVersion: harbor的版本

harborDataVolume: harbor的数据存储卷路径

chartRepo: 独立chartmuseum的url，需要配置harborWithChartmusuem为"false"才能生效

ldapOrgName: 用于在启动ldap时指定的LDAP_ORGANISATION环境变量，无明确影响

ldapDomain: ldap的域名

ldapBindDN: ldap的bind DN

ldapRootPW: ldap的管理员密码

dexDNS: dex域名

loginappDNS: loginapp的域名

oidcUsernamePrefix: ldap中用户在k8s中的命名前缀，例如ldap中的用户为zhangsan，那么在k8s中就是<前缀>+zhangsan

loginappProxyDNS: loginapp-proxy的域名

peerIP: 弃用

peerRootPW: 弃用

infraVIPs: 镜像仓库、ldap等基础架构组件的VIP信息

pkgRepoHosts: 软件仓库/yum源的IP和密码信息

imgRepoHosts: 镜像仓库的IP和密码信息

ldapHosts: ldap的IP和密码信息

haproxyHosts: 弃用

defaultIngress: 默认使用的ingress类型，待支持

platformDNSRootDomains: 平台内部服务的根域名

enablePrometheus: 是否开启prometheus

enableEtcdTool: 是否开启etcdTool

etcdToolTag: etcdTool的版本
