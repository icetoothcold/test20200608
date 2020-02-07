*************
Dex组件的说明
*************

简述
====

loginapp-proxy通过loginapp向dex获取token，客户端拿到token后向apiserver请求，apiserver看到token后问dex:"是不是你签发的token"，dex说:"是的"，那么这就是一个来自合法用户的请求。

组件
====

dex全家桶包括: dex, loginapp, loginapp-proxy。

dex用于签发token:

  - dex会链接类似ldap这样用户注册中心，将接受到的请求(用户名，密码)在ldap中进行查询，如果能查询到，就说明提交的请求有效，那么将生成一个token，并返回；
  - 因此，dex的配置中需要配置ldap的域名信息，bind DN，以及ldap admin密码；
  - 目前，dex的配置中需要同时配置people和group的查询方式，因此在k8s的RBAC中，创建的组可以关联到ldap中的组；
  - 产生的token将由dex通过创建Custom Resource的方式存储在k8s中；

loginapp用于向dex发起获取token的请求:

  - 需要在dex中配置静态客户端信息，loginapp使用静态客户端信息来向dex发起访问；
  - dex通过https对外暴露，因此loginapp中需要配置dex的证书，因此需要将证书挂到ingress上；
  - dex在接受到请求，向ldap验证通过后，会调用loginapp的回调接口来返回结果，因此两边都会需要配置同一个回调接口；

loginapp-proxy用于向loginapp提供代理:

  - loginapp目前只提供了web界面来获取token，不适合我们使用，因此写了一个简单的代理，以API的方式返回token；
  - loginapp-proxy为了避免走ingress，采用走service的方式，因此在deployment中需要指定dex和loginapp-proxy的svc;

apiserver
=========

由dex签发的token，在经过loginapp和loginapp-proxy传递给客户端或者用户后，客户端可以通过如下方式发起K8S API访问:

::
	curl -H "Authorization: Bearer $token" -k https://<APISERVER_IP>:<PORT>/api/v1/...

apiserver在接受到请求后，需要对token进行验证，因此在kube-apiserver的配置中，需要配置dex的信息，使得kube-apiserver可以调用dex以验证token是dex签发的有效token。
