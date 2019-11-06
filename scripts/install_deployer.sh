skipFirstN=0    # set -1 will skip all tasks to check taskId
skipLastFrom=0
notSkip=()      # can work with skipFirstN=-1


rootPath="$(cd `dirname $0`; cd .. ; pwd)"
source $rootPath/scripts/utils.sh

install_deployer_check
if [[ $checkFailed -eq 1 ]]; then
    exit 1
fi

startTime=`date +%s`

if [[ -z $myIP ]]; then
    echo "IP check failed..."
    exit
fi
echo "IP check pass..."

echo_task "extract tar packages"
if [[ $skipped -ne 1 ]]; then
    extract_tar_packages
fi

echo_task "add infra domain into /etc/hosts"
if [[ $skipped -ne 1 ]]; then
    for i in "$pkgRepoHost" "$imgRepo" "$chartRepoHost" "$ldapDomain"; do
        grep -q $i /etc/hosts
        if [[ $? -ne 0 ]]; then
            echo "$myIP  $i" >> /etc/hosts
        fi
    done
fi

echo_task "disable firewalld service"
if [[ $skipped -ne 1 ]]; then
    systemctl stop firewalld
    systemctl disable firewalld
fi

echo_task "localinstall iptables and iptables service"
if [[ $skipped -ne 1 ]]; then
    pushd $rpmsPath
    yum localinstall -y iptables* 
    popd
fi

echo_task "save clean iptables"
if [[ $skipped -ne 1 ]]; then
    touch /etc/sysconfig/iptables
    touch /etc/sysconfig/ip6tables
    cp /etc/sysconfig/iptables /etc/sysconfig/iptables-`date +%s`
    cp /etc/sysconfig/ip6tables /etc/sysconfig/ip6tables-`date +%s`
    iptables-save >/etc/sysconfig/iptables
    ip6tables-save >/etc/sysconfig/ip6tables
fi

echo_task "localinstall necessary packages, including docker-ce, selinux, ..."
if [[ $skipped -ne 1 ]]; then
    pushd $rpmsPath
    yum localinstall -y audit* checkpolicy* containerd.io* container-selinux* docker-ce* libcgroup* libselinux* libsemanage* libsepol* policycoreutils* python-IPy* selinux-policy* setools-libs* pcre-devel*
    popd
fi

echo_task "add insecure-registry"
if [[ $skipped -ne 1 ]]; then
    sed -i "/ExecStart=/ s/$/ --insecure-registry=$imgRepo/" /usr/lib/systemd/system/docker.service
    systemctl daemon-reload
fi

echo_task "systemctl enable and start docker"
if [[ $skipped -ne 1 ]]; then
    systemctl enable docker
    systemctl start docker
fi

echo_task "customize some download file"
if [[ $skipped -ne 1 ]]; then
    sed -i "s#https://github.com#$pkgRepo#g" $rpmsPath/helm-push_install_plugin.sh
fi

echo_task "load onecache image"
if [[ $skipped -ne 1 ]]; then
    image=`ls $imgPath | grep onecache`
    docker load < $imgPath/$image
    docker tag onecache $imgRepo/library/onecache
fi

echo_task "start local repo"
if [[ $skipped -ne 1 ]]; then
    bash $scriptPath/start_repo.sh
    if [[ `verify_repo_up "repo"` -ne 1 ]]; then
	    echo "After 1 min, local repo up detect failed..."
	    exit 1
    fi
fi

echo_task "backup current yum repos"
if [[ $skipped -ne 1 ]]; then
    pushd /etc/yum.repos.d
    mkdir bak
    mv *.repo bak
    popd
fi

echo_task "get private repo"
if [[ $skipped -ne 1 ]]; then
    curl --retry 10 --retry-delay 3 --retry-max-time 30 $pkgRepo/private.repo -o /etc/yum.repos.d/private.repo
fi

echo_task "start chartmuseum"
if [[ $skipped -ne 1 ]]; then
    image=`ls $imgPath | grep chartmuseum`
    docker load < $imgPath/$image
    docker tag chartmuseum/chartmuseum $imgRepo/chartmuseum/chartmuseum
    bash $scriptPath/start_chartmuseum.sh
fi

echo_task "yum install docker-compose"
if [[ $skipped -ne 1 ]]; then
    yum -y install docker-compose
fi

echo_task "install harbor"
if [[ $skipped -ne 1 ]]; then
    curl $pkgRepo/harbor-offline-installer-v1.8.1.tgz -o $rootPath/harbor-offline-installer-v1.8.1.tgz
    tar xf $rootPath/harbor-offline-installer-v1.8.1.tgz -C $rootPath
    rm -f $rootPath/harbor-offline-installer-v1.8.1.tgz
    pushd $rootPath/harbor
    sed -i -e "s/^hostname:.*/hostname: $imgRepo/" -e "s/^harbor_admin_password:.*/harbor_admin_password: $harborAdminPw/" harbor.yml
    ./install.sh
    rm -f harbor.v1.8.1.tar.gz
    popd
    if [[ `verify_repo_up "harbor"` -ne 1 ]]; then
        echo "Failed to login harbor after 1 min..."
        exit 1
    fi
fi

echo_task "load images to harbor"
if [[ $skipped -ne 1 ]]; then
    bash $scriptPath/load_images.sh
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
fi

echo_task "install and config pip3.6"
if [[ $skipped -ne 1 ]]; then
    yum install -y python36 python36-pip
    pip3.6 install -i http://$pkgRepoHost:$pypiPort/simple --trusted-host $pkgRepoHost pip -U
    ln -s /usr/local/bin/pip3.6 /usr/bin/pip3.6
    pip3.6 config set global.index-url http://$pkgRepoHost:$pypiPort/simple
    pip3.6 config set global.trusted-host $pkgRepoHost
fi

echo_task "install requirements for kubespray"
if [[ $skipped -ne 1 ]]; then
    pushd $rootPath/kubespray
    pip3.6 install -r requirements.txt
    pip3.6 install jinja2-cli
    popd
fi

echo_task "install ssh-copy-id and sshpass"
if [[ $skipped -ne 1 ]]; then
    yum install -y openssh-clients sshpass
fi

echo_task "generate ssh keys"
if [[ $skipped -ne 1 ]]; then
    ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
fi

echo_task "install helm client"
if [[ $skipped -ne 1 ]]; then
    curl $pkgRepo/helm/v2.14.3/linux/amd64/helm -o /usr/sbin/helm
    chmod u+x /usr/sbin/helm
    helm init --client-only --stable-repo-url $chartRepo/$localInfraChartRepo
fi

echo_task "add ExecStartPost to docker service"
if [[ $skipped -ne 1 ]]; then
    grep -q "repo_startpost.sh" /usr/lib/systemd/system/docker.service
    if [[ $? -ne 0 ]]; then
        sed -i "/^Restart=/aExecStartPost=\/usr\/bin\/bash $scriptPath\/repo_startpost.sh" /usr/lib/systemd/system/docker.service
    fi
set -x
    systemctl daemon-reload
    systemctl restart docker
set +x
    if [[ `verify_repo_up "repo"` -ne 1 ]]; then
	    echo "After 1 min, local repo up detect failed..."
	    exit 1
    fi
fi

echo_task "install helm push plugin"
if [[ $skipped -ne 1 ]]; then
    curl $pkgRepo/helm-push.tar -o $rootPath/helm-push.tar
    tar xf $rootPath/helm-push.tar -C $rootPath
    curl $pkgRepo/helm-push_install_plugin.sh -o $rootPath/helm-push/scripts/install_plugin.sh
    helm plugin install $rootPath/helm-push
    rm -f $rootPath/helm-push.tar
fi

echo_task "install openldap-clients"
if [[ $skipped -ne 1 ]]; then
    yum install -y openldap-clients
fi

echo_task "start ldap"
if [[ $skipped -ne 1 ]]; then
    bash $scriptPath/start_ldap.sh
    if [[ `verify_repo_up "ldap"` -ne 1 ]]; then
        echo "After 1 min, local ldap up detect failed..."
        exit 1
    fi
fi

echo_task "enable ldap memberof"
if [[ $skipped -ne 1 ]]; then
    docker cp $scriptPath/ldap_memberof ldap:.
    docker exec -it ldap "/bin/bash" "/ldap_memberof/cmd"
fi

echo_task "set harbor auth_mode to ldap"
if [[ $skipped -ne 1 ]]; then
    curl -X PUT -u "admin:$harborAdminPw" -H "Content-Type: application/json" -ki http://$imgRepo/api/configurations \
        -d '{"auth_mode":"ldap_auth","ldap_url":"ldap://'$ldapDomain':389","ldap_search_dn":"cn=admin,'$ldapBindDN'","ldap_search_password":"'$ldapRootPW'","ldap_base_dn":"ou=People,'$ldapBindDN'","ldap_filter":"(objectClass=person)","ldap_uid":"cn","ldap_scope":"2","ldap_timeout":"5","ldap_verify_cert":"false","ldap_group_base_dn":"ou=Groups,'$ldapBindDN'","ldap_group_admin_dn":"ou=Groups,'$ldapBindDN'","ldap_group_search_filter":"objectClass=groupOfNames","ldap_group_attribute_name":"cn","ldap_group_search_scope":"2","ldap_group_membership_attribute":"memberof","self_registration":"false","project_creation_restriction":"adminonly"}'
fi

echo_task "set harbor gc schedule"
if [[ $skipped -ne 1 ]]; then
    curl -X POST -u "admin:$harborAdminPw" -H "Content-Type: application/json" -ki http://$imgRepo/api/system/gc/schedule -d "{\"schedule\":{\"type\":\"Custom\",\"cron\":\"$harborGcCron\"}}"
fi

echo_task "add tests users into ldap"
if [[ $skipped -ne 1 ]]; then
    ldapadd -x -H ldap://$ldapDomain:389 -D "cn=admin,$ldapBindDN" -w $ldapRootPW -f $rootPath/tests/dex-example-config-ldap.ldif
fi

#echo_task ""
#if [[ $skipped -ne 1 ]]; then
#fi

echo -e "\n\nAll tasks done!"
if [[ $skipFirstN -eq 0 && $skipLastFrom -eq 0 ]]; then
    echo "Spend seconds: $((`date +%s`-startTime))"
fi
echo "Next:"
echo -e "\t(optional) to upgrade to HA, deploy a HA peer run:"
echo -e "\t    $scriptPath/upgrade_ha_deployers.sh\n"
echo -e "\tEnsure your cluster file is under $clusterPath, then run:"
echo -e "\t$scriptPath/pre_deploy_stage_1.sh <YOUR_CLUSTER_NAME>"
