skipFirstN=0    # set -1 will skip all tasks to check taskId
skipLastFrom=0
notSkip=()      # can work with skipFirstN=-1


rootPath="$(cd `dirname $0`; cd .. ; pwd)"
source $rootPath/scripts/utils.sh

startTime=`date +%s`

if [[ -z $peerIP || -z $peerRootPW ]]; then
    echo "No peer info found..."
    exit
fi
echo "Peer info check pass..."

if [[ -z $imageRepoVIP || -z $pkgRepoVIP || -z $chartRepoVIP || -z $ldapVIP ]]; then
    echo "VIPs check failed..."
    exit
fi
echo "VIPs check pass..."

echo_task "insert ssh key to peer authorized_keys"
if [[ $skipped -ne 1 ]]; then
    ssh-keyscan $peerIP >> ~/.ssh/known_hosts
    sshpass -p $peerRootPW ssh-copy-id -f root@$peerIP
fi

echo_task "update insecure-registry and reload docker"
if [[ $skipped -ne 1 ]]; then
    sed -i "/ExecStart=/ s/$/ --insecure-registry=$imgRepo --insecure-registry=$myIP --insecure-registry=$peerIP/" /usr/lib/systemd/system/docker.service
    systemctl daemon-reload
    systemctl enable docker
    systemctl restart docker
fi

echo_task "temporary add VIP"
if [[ $skipped -ne 1 ]]; then
    add_pkg_repo_tmp_vip
fi

echo_task "re-configure harbor"
if [[ $skipped -ne 1 ]]; then
    pushd $rootPath/harbor
    docker-compose down
    mv /data/{database,redis,registry,secret} $harborShareVolume
    sed -i -e "s#/data/registry#$harborShareVolume/registry#" -e "s#/data/redis#$harborShareVolume/redis#" -e "s#/data/database#$harborShareVolume/database#" -e "s#/data/secret#/$harborShareVolume/secret#" docker-compose.yml
    docker-compose up -d
    popd
    if [[ `verify_repo_up "harbor" "$myIP"` -ne 1 ]]; then
        echo "Failed to login harbor after 1 min..."
        exit 1
    fi
fi

echo_task "start ldap ha"
if [[ $skipped -ne 1 ]]; then
    bash $scriptPath/start_ldap_ha.sh
    if [[ `verify_repo_up "ldap" "$myIP:$ldapHABackendPort"` -ne 1 ]]; then
        echo "After 1 min, local ldap up detect failed..."
        exit 1
    fi
fi

echo_task "start haproxy"
if [[ $skipped -ne 1 ]]; then
    jinja2 $templatePath/haproxy.repo.cfg.tml $rootPath/infra.yml --format=yaml > $templatePath/haproxy.repo.cfg
    bash $scriptPath/start_haproxy.sh
fi

echo_task "start keepalived"
if [[ $skipped -ne 1 ]]; then
    bash $scriptPath/start_keepalived.sh
fi

echo_task "peer: generate ssh keys"
if [[ $skipped -ne 1 ]]; then
    ssh root@$peerIP "ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa"
fi

echo_task "peer: insert infra domains into hosts"
if [[ $skipped -ne 1 ]]; then
    ssh root@$peerIP "echo $imageRepoVIP $imgRepo >> /etc/hosts"
    ssh root@$peerIP "echo $pkgRepoVIP $pkgRepoHost >> /etc/hosts"
    ssh root@$peerIP "echo $chartRepoVIP $chartRepoHost >> /etc/hosts"
    ssh root@$peerIP "echo $ldapVIP $ldapDomain >> /etc/hosts"
fi

echo_task "peer: backup host repo, and install private repo"
if [[ $skipped -ne 1 ]]; then
    ssh root@$peerIP "mkdir /etc/yum.repos.d/bak; mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak; curl $pkgRepo/private.repo -o /etc/yum.repos.d/private.repo; yum clean all"
fi

echo_task "peer: install requirements"
if [[ $skipped -ne 1 ]]; then
    ssh root@$peerIP "yum install -y iptables iptables-service iptables-utils docker-ce docker-compose python36 python36-pip openldap-clients containerd.io openssh-clients sshpass"
fi

echo_task "peer: disable firewalld service and save clean iptables"
if [[ $skipped -ne 1 ]]; then
    ts=`date +%s`
    ssh root@$peerIP "systemctl stop firewalld; systemctl disable firewalld; touch /etc/sysconfig/iptables; touch /etc/sysconfig/ip6tables; cp /etc/sysconfig/iptables /etc/sysconfig/iptables-$ts; cp /etc/sysconfig/ip6tables /etc/sysconfig/ip6tables-$ts; iptables-save >/etc/sysconfig/iptables; ip6tables-save >/etc/sysconfig/ip6tables"
fi

echo_task "peer: add insecure-registry and enable docker"
if [[ $skipped -ne 1 ]]; then
    ssh root@$peerIP "sed -i '/ExecStart=/ s/$/ --insecure-registry=$imgRepot --insecure-registry=$myIP --insecure-registry=$peerIP/' /usr/lib/systemd/system/docker.service; systemctl daemon-reload; systemctl enable docker; systemctl start docker"
fi

echo_task "peer: config pip3.6"
if [[ $skipped -ne 1 ]]; then
    ssh root@$peerIP "pip3.6 install -i http://$pkgRepoHost:$pypiPort/simple --trusted-host $pkgRepoHost pip -U; ln -s /usr/local/bin/pip3.6 /usr/bin/pip3.6; pip3.6 config set global.index-url http://$pkgRepoHost:$pypiPort/simple; pip3.6 config set global.trusted-host $pkgRepoHost"
fi

echo_task "peer: pip install requirements"
if [[ $skipped -ne 1 ]]; then
    ssh root@$peerIP "pip3.6 install ansible jinja2 netaddr pbr hvac jmespath ruamel.yaml jinja2-cli"
fi

echo_task "peer: install helm client"
if [[ $skipped -ne 1 ]]; then
    ssh root@$peerIP "curl $pkgRepo/helm/v2.14.3/linux/amd64/helm -o /usr/sbin/helm; chmod u+x /usr/sbin/helm; helm init --client-only --stable-repo-url $chartRepo/$localInfraChartRepo"
fi

echo_task "peer: install helm push plugin"
if [[ $skipped -ne 1 ]]; then
    ssh root@$peerIP "curl $pkgRepo/helm-push.tar -o helm-push.tar; tar xf helm-push.tar; curl $pkgRepo/helm-push_install_plugin.sh -o helm-push/scripts/install_plugin.sh; helm plugin install helm-push; rm -f helm-push.tar"
fi

echo_task "update infra domain IPs in /etc/hosts"
if [[ $skipped -ne 1 ]]; then
    sed -i "s/.*$imgRepo/$imageRepoVIP $imgRepo/" /etc/hosts
    sed -i "s/.*$pkgRepoHost/$pkgRepoVIP $pkgRepoHost/" /etc/hosts
    sed -i "s/.*$chartRepoHost/$chartRepoVIP $chartRepoHost/" /etc/hosts
    sed -i "s/.*$ldapDomain/$ldapVIP $ldapDomain/" /etc/hosts
fi

echo_task "sync infra.yml scripts templates to peer"
if [[ $skipped -ne 1 ]]; then
    ssh root@$peerIP "mkdir -p $rootPath"
    scp -r $rootPath/infra.yml $scriptPath $templatePath root@$peerIP:$rootPath
fi

echo_task "peer: start ldap ha"
if [[ $skipped -ne 1 ]]; then
    ssh root@$peerIP "bash $scriptPath/start_ldap_ha.sh"
    if [[ `verify_repo_up "ldap" "$peerIP:$ldapHABackendPort"` -ne 1 ]]; then
        echo "After 1 min, local ldap up detect failed..."
        exit 1
    fi
fi

echo_task "peer: install harbor"
if [[ $skipped -ne 1 ]]; then
    ssh root@$peerIP "cd $rootPath; curl $pkgRepo/harbor-offline-installer-v1.8.1.tgz -o harbor-offline-installer-v1.8.1.tgz; tar xf harbor-offline-installer-v1.8.1.tgz; rm -f harbor-offline-installer-v1.8.1.tgz; cd harbor; sed -i -e 's/^hostname:.*/hostname: $imgRepo/' -e 's/^harbor_admin_password:.*/harbor_admin_password: $harborAdminPw/' harbor.yml; ./install.sh; rm -f harbor.v1.8.1.tar.gz"
    if [[ `verify_repo_up "harbor" "$peerIP"` -ne 1 ]]; then
        echo "Failed to login harbor after 1 min..."
        exit 1
    fi
fi

echo_task "peer: re-configure harbor"
if [[ $skipped -ne 1 ]]; then
    ssh root@$peerIP "cd $rootPath/harbor; docker-compose down; rm -rf /data/{database,redis,registry}; sed -i -e 's#/data/registry#$harborShareVolume/registry#' -e 's#/data/redis#$harborShareVolume/redis#' -e 's#/data/database#$harborShareVolume/database#' -e 's#/data/secret#/$harborShareVolume/secret#' docker-compose.yml; docker-compose up -d"
    if [[ `verify_repo_up "harbor" "$peerIP"` -ne 1 ]]; then
        echo "Failed to login harbor after 1 min..."
        exit 1
    fi
fi

echo_task "peer: start haproxy"
if [[ $skipped -ne 1 ]]; then
    ssh root@$peerIP "jinja2 $templatePath/haproxy.repo.cfg.tml $rootPath/infra.yml --format=yaml > $templatePath/haproxy.repo.cfg; bash $scriptPath/start_haproxy.sh"
fi

echo_task "peer: start keepalived"
if [[ $skipped -ne 1 ]]; then
    ssh root@$peerIP "bash $scriptPath/start_keepalived.sh"
fi

#echo_task "start lsyncd" // peer ?
#if [[ $skipped -ne 1 ]]; then
#fi

#echo_task "peer: start repo"
#if [[ $skipped -ne 1 ]]; then
#fi

#echo_task "start chartmuseum"
#if [[ $skipped -ne 1 ]]; then
#fi

#echo_task "peer: add ExecStartPost to docker service"
#if [[ $skipped -ne 1 ]]; then
#    ssh root@$peerIP "if [[ \`grep -c 'repo_startpost.sh' /usr/lib/systemd/system/docker.service\` -eq 0 ]]; then sed -i '/^Restart=/aExecStartPost=\/usr\/bin\/bash $scriptPath\/repo_startpost.sh' /usr/lib/systemd/system/docker.service; fi; systemctl daemon-reload; systemctl restart docker"
#    if [[ `verify_repo_up "repo" "$peerIP"` -ne 1 ]]; then
#	    echo "After 1 min, local repo up detect failed..."
#	    exit 1
#    fi
#fi

#echo_task ""
#if [[ $skipped -ne 1 ]]; then
#fi

echo -e "\n\nAll tasks done!"
if [[ $skipFirstN -eq 0 && $skipLastFrom -eq 0 ]]; then
    echo "Spend seconds: $((`date +%s`-startTime))"
fi
echo "Next, ensure your cluster file is under $clusterPath, then run:"
echo -e "\t$scriptPath/pre_deploy_stage_1.sh <YOUR_CLUSTER_NAME>"
