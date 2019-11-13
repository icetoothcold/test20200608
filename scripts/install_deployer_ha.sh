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

echo_task "generate ssh keys"
if [[ $skipped -ne 1 ]]; then
    if [[ ! -f ~/.ssh/id_rsa.pub || ! -f ~/.ssh/id_rsa || `diff <( ssh-keygen -yef ~/.ssh/id_rsa.pub ) <( ssh-keygen -yef ~/.ssh/id_rsa ) | wc -l` -ne 0 ]]; then
        ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
    else
        echo -ne "\nssh rsa key already exists, nothing to do..."
    fi
fi

echo_task "backup local current yum repos"
if [[ $skipped -ne 1 ]]; then
    mkdir /etc/yum.repos.d/bak
    mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak
fi

echo_task "yum localinstall: ssh-copy-id, sshpass"
if [[ $skipped -ne 1 ]]; then
    pushd $rpmsPath
    yum localinstall -y openssh-* sshpass*
    popd
fi

echo_task "ssh authorize infra nodes"
if [[ $skipped -ne 1 ]]; then
    uniqList=""
    for ipPwd in `walk_infra_hosts "${imgRepoHosts[@]} ${ldapHosts[@]} ${haproxyHosts[@]}"`; do
        if [[ `echo $uniqList | grep -c $ipPwd` -eq 0 ]]; then
            uniqList="$ipPwd ${uniqList[@]}"
        fi
    done
    for ipPwd in ${uniqList[@]}; do
        ip=`echo $ipPwd | cut -d ':' -f 1`
        rootPw=`echo $ipPwd | cut -d ':' -f 2`
        ssh_authorize $ip $rootPw
    done
fi

echo_task "localinstall docker-ce"
if [[ $skipped -ne 1 ]]; then
    pushd $rpmsPath
    yum localinstall -y audit* checkpolicy* containerd.io* container-selinux* docker-ce* libcgroup* libselinux* libsemanage* libsepol* policycoreutils* python-IPy* selinux-policy* setools-libs* pcre-devel*
    popd
    systemctl start docker
fi

echo_task "add infra domain into /etc/hosts"
if [[ $skipped -ne 1 ]]; then
    ips=`get_all_infra_ips`
    insert_hosts "${ips[@]}" $imgRepo $imageRepoVIP
    insert_hosts "${ips[@]}" $pkgRepoHost $pkgRepoVIP
    insert_hosts "${ips[@]}" $chartRepoHost $chartRepoVIP
    insert_hosts "${ips[@]}" $ldapDomain $ldapVIP
fi

echo_task "temporary add VIP"
if [[ $skipped -ne 1 ]]; then
    add_pkg_repo_tmp_vip
fi

echo_task "start local pkg repo"
if [[ $skipped -ne 1 ]]; then
    image=`ls $imgPath | grep onecache`
    docker load < $imgPath/$image
    docker tag onecache $imgRepo/library/onecache
    bash $scriptPath/start_repo.sh
    if [[ `verify_repo_up "repo"` -ne 1 ]]; then
	    echo "After 1 min, local repo up detect failed..."
	    exit 1
    fi
fi

echo_task "backup current yum repos and get private repo"
if [[ $skipped -ne 1 ]]; then
    for ip in `get_all_infra_ips`; do
        ssh root@$ip "$CMD_BACKUP_YUM_REPOS ; curl --retry 10 --retry-delay 3 --retry-max-time 30 $pkgRepo/private.repo -o /etc/yum.repos.d/private.repo; yum clean all"
    done
fi

echo_task "install and configure: iptables"
if [[ $skipped -ne 1 ]]; then
    for ip in `get_all_infra_ips`; do
        ssh root@$ip "yum install -y iptables iptables-services iptables-utils; $CMD_DISABLE_FIREWALLD; $CMD_BACKUP_IPTABLES"
    done
fi

echo_task "install and configure: docker-ce"
if [[ $skipped -ne 1 ]]; then
    insecReg=""
    for ip in `get_infra_ips "${imgRepoHosts[@]}"`; do
        insecReg="--insecure-registry=$ip ${insecReg[@]}"
    done
    for ip in `get_all_infra_ips`; do
        ssh root@$ip "yum install -y docker-ce; sed -i '/ExecStart=/ s/$/ --insecure-registry=$imgRepo ${insecReg[@]}/' /usr/lib/systemd/system/docker.service; $CMD_SYSTEMCTL_RESTART_DOCKER"
        if [[ `ip a | grep -c $ip` -eq 1 ]]; then
            bash $scriptPath/start_repo.sh
            if [[ `verify_repo_up "repo"` -ne 1 ]]; then
	            echo "After 1 min, local repo up detect failed..."
	            exit 1
            fi
        fi
    done
fi

echo_task "install and configure: pip3.6, jinja2-cli"
if [[ $skipped -ne 1 ]]; then
    for ip in `get_all_infra_ips`; do
        ssh root@$ip "yum install -y python36 python36-pip; $CMD_CONFIG_PIP ; pip3.6 install jinja2-cli"
    done
fi

echo_task "install openldap-clients"
if [[ $skipped -ne 1 ]]; then
    for ip in `get_infra_ips "${ldapHosts[@]}"`; do
        ssh root@$ip "yum install -y openldap-clients"
    done
fi

echo_task "cp to infra nodes: scripts, templates, infra.yml"
if [[ $skipped -ne 1 ]]; then
    for ip in `get_all_infra_ips`; do
        ssh root@$ip "mkdir -p $rootPath/{scripts,templates}"
        scp -r $rootPath/infra.yml $scriptPath $templatePath root@$ip:$rootPath
    done
fi

echo_task "install docker-compose, harbor"
if [[ $skipped -ne 1 ]]; then
    ips=`get_infra_ips "${imgRepoHosts[@]}"`
    firstImgRepoIP=`echo ${ips[@]} | cut -d ' ' -f 1`
    for ip in ${ips[@]}; do
        ssh root@$ip "yum -y install docker-compose; $CMD_GET_EXTRACT_HARBOR ; cd harbor; $CMD_MODIFY_HARBOR_HOST_PSWD ; ./install.sh; rm -f harbor.v1.8.1.tar.gz"
        if [[ `verify_repo_up "harbor" "$ip"` -ne 1 ]]; then
            echo "Failed to login harbor after 1 min..."
            exit 1
        fi
    done
fi

echo_task "re-configure harbor"
if [[ $skipped -ne 1 ]]; then
    ips=`get_infra_ips "${imgRepoHosts[@]}"`
    firstImgRepoIP=`echo ${ips[@]} | cut -d ' ' -f 1`
    for ip in ${ips[@]}; do
        if [[ "$ip" == "$firstImgRepoIP" ]]; then
            ssh root@$ip "rm -rf $harborShareVolume/{database,redis,registry,secret}; mv /data/{database,redis,registry,secret} $harborShareVolume; cd $rootPath/harbor; docker-compose down; sed -i -e 's#/data/registry#$harborShareVolume/registry#' -e 's#/data/redis#$harborShareVolume/redis#' -e 's#/data/database#$harborShareVolume/database#' -e 's#/data/secret#$harborShareVolume/secret#' docker-compose.yml; docker-compose up -d"
        else
            ssh root@$ip "cd $rootPath/harbor; docker-compose down; rm -rf /data/{database,redis,registry,secret}; sed -i -e 's#/data/registry#$harborShareVolume/registry#' -e 's#/data/redis#$harborShareVolume/redis#' -e 's#/data/database#$harborShareVolume/database#' -e 's#/data/secret#$harborShareVolume/secret#' docker-compose.yml; docker-compose up -d"
        fi
        if [[ `verify_repo_up "harbor" "$ip"` -ne 1 ]]; then
            echo "Failed to login harbor after 1 min..."
            exit 1
        fi
    done
fi

echo_task "start haproxy"
if [[ $skipped -ne 1 ]]; then
    tmpData="data.tmp`date +%s`"
    ldapIPs=`get_infra_ips "${ldapHosts[@]}"`
    imgRepoIPs=`get_infra_ips "${imgRepoHosts[@]}"`
    for ip in `get_infra_ips "${haproxyHosts[@]}"`; do
        scp $imgPath/haproxy.tar root@$ip:.
        ssh root@$ip "docker load < haproxy.tar; rm -f haproxy.tar; docker tag haproxy $imgRepo/library/haproxy; cat $rootPath/infra.yml > $tmpData; echo 'ldapIPs: $ldapIPs' >> $tmpData; jinja2 $templatePath/haproxy.repo.cfg.tml $tmpData --format=yaml > $templatePath/haproxy.repo.cfg; bash $scriptPath/start_haproxy.sh; rm -f $tmpData"
    done
fi

echo_task "start keepalived, remove temporary VIP and verify"
if [[ $skipped -ne 1 ]]; then
    ips=`get_infra_ips "${imgRepoHosts[@]}"`
    firstImgRepoIP=`echo ${ips[@]} | cut -d ' ' -f 1`
    for ip in `get_infra_ips "${haproxyHosts[@]}"`; do
        scp $imgPath/keepalived-vip.${keepalivedTag}.tar root@$ip:.
        ssh root@$ip "docker load < keepalived-vip.${keepalivedTag}.tar; rm -f keepalived-vip.${keepalivedTag}.tar; docker tag keepalived-vip:$keepalivedTag $imgRepo/library/keepalived-vip:$keepalivedTag; bash $scriptPath/start_keepalived.sh"
    done
    ssh root@$firstImgRepoIP "ip a del dev \$(ip r get 8.8.8.8 | awk '/dev/{print \$5}) $imgRepoVIP/32"
    if [[ `verify_repo_up "vip" "$imageRepoVIP"` -ne 1 ]]; then
        echo "After 1 min, keepalived-vip for imgRepoVIP($imgRepoVIP) detect failed..."
        exit 1
    fi
    if [[ `verify_repo_up "vip" "$ldapVIP"` -ne 1 ]]; then
        echo "After 1 min, keepalived-vip for ldapVIP($ldapVIP) detect failed..."
        exit 1
    fi
fi

echo_task "load images to harbor"
if [[ $skipped -ne 1 ]]; then
    ips=`get_infra_ips "${imgRepoHosts[@]}"`
    firstImgRepoIP=`echo ${ips[@]} | cut -d ' ' -f 1`
    if [[ `echo ${ips[@]} | grep -c $myIP` -eq 1 ]]; then
        bash $scriptPath/load_images.sh
    else
        scp -r $imgPath root@$firstIP:$rootPath
        ssh root@$firstImgRepoIP "bash $scriptPath/load_images.sh"
    fi
    if [[ $? -ne 0 ]]; then
        echo "failed to load images to harbor"
        exit 1
    fi
fi

echo_task "start ldap"
if [[ $skipped -ne 1 ]]; then
    for ip in `get_infra_ips "${ldapHosts[@]}"`; do
        ssh root@$ip "bash $scriptPath/start_ldap_ha.sh"
        if [[ `verify_repo_up "ldap" "$ip:389"` -ne 1 ]]; then
            echo "After 1 min, local ldap up detect failed..."
            exit 1
        fi
    done
fi

echo_task "enable ldap memberof"
if [[ $skipped -ne 1 ]]; then
    firstIP=`get_infra_ips "${ldapHosts[@]}" | cut -d ' ' -f 1`
    ssh root@$firstIP "docker cp $scriptPath/ldap_memberof ldap:.; docker exec ldap '/bin/bash' '/ldap_memberof/cmd'"
fi

echo_task "configure: harbor: set ldap auth_mode, and gc schedule"
if [[ $skipped -ne 1 ]]; then
    firstIP=`get_infra_ips "${imgRepoHosts[@]}" | cut -d ' ' -f 1`
    ssh root@$firstIP "curl -X PUT -u 'admin:$harborAdminPw' -H 'Content-Type: application/json' -ki http://$imgRepo/api/configurations -d '{\"auth_mode\":\"ldap_auth\",\"ldap_url\":\"ldap://$ldapDomain:389\",\"ldap_search_dn\":\"cn=admin,$ldapBindDN\",\"ldap_search_password\":\"$ldapRootPW\",\"ldap_base_dn\":\"ou=People,$ldapBindDN\",\"ldap_filter\":\"(objectClass=person)\",\"ldap_uid\":\"cn\",\"ldap_scope\":\"2\",\"ldap_timeout\":\"5\",\"ldap_verify_cert\":\"false\",\"ldap_group_base_dn\":\"ou=Groups,$ldapBindDN\",\"ldap_group_admin_dn\":\"ou=Groups,$ldapBindDN\",\"ldap_group_search_filter\":\"objectClass=groupOfNames\",\"ldap_group_attribute_name\":\"cn\",\"ldap_group_search_scope\":\"2\",\"ldap_group_membership_attribute\":\"memberof\",\"self_registration\":\"false\",\"project_creation_restriction\":\"adminonly\"}'"
    ssh root@$firstIP "curl -X POST -u 'admin:$harborAdminPw' -H 'Content-Type: application/json' -ki http://$imgRepo/api/system/gc/schedule -d '{\"schedule\":{\"type\":\"Custom\",\"cron\":\"$harborGcCron\"}}'"
fi

echo_task "customize some download file"
if [[ $skipped -ne 1 ]]; then
    sed -i "s#https://github.com#$pkgRepo#g" $rpmsPath/helm-push_install_plugin.sh
fi

echo_task "start chartmuseum"
if [[ $skipped -ne 1 ]]; then
    image=`ls $imgPath | grep chartmuseum`
    docker load < $imgPath/$image
    docker tag chartmuseum/chartmuseum $imgRepo/chartmuseum/chartmuseum
    bash $scriptPath/start_chartmuseum.sh
fi

echo_task "install requirements for kubespray"
if [[ $skipped -ne 1 ]]; then
    pushd $rootPath/kubespray
    pip3.6 install -r requirements.txt
    popd
fi

echo_task "install helm client"
if [[ $skipped -ne 1 ]]; then
    curl $pkgRepo/helm/v2.14.3/linux/amd64/helm -o /usr/sbin/helm
    chmod u+x /usr/sbin/helm
    helm init --client-only --stable-repo-url $chartRepo/$localInfraChartRepo
fi

#echo_task "add ExecStartPost to docker service"
#if [[ $skipped -ne 1 ]]; then
#    grep -q "repo_startpost.sh" /usr/lib/systemd/system/docker.service
#    if [[ $? -ne 0 ]]; then
#        sed -i "/^Restart=/aExecStartPost=\/usr\/bin\/bash $scriptPath\/repo_startpost.sh" /usr/lib/systemd/system/docker.service
#    fi
#set -x
#    systemctl daemon-reload
#    systemctl restart docker
#set +x
#    if [[ `verify_repo_up "repo"` -ne 1 ]]; then
#	    echo "After 1 min, local repo up detect failed..."
#	    exit 1
#    fi
#fi

echo_task "install helm push plugin"
if [[ $skipped -ne 1 ]]; then
    curl $pkgRepo/helm-push.tar -o $rootPath/helm-push.tar
    tar xf $rootPath/helm-push.tar -C $rootPath
    curl $pkgRepo/helm-push_install_plugin.sh -o $rootPath/helm-push/scripts/install_plugin.sh
    helm plugin install $rootPath/helm-push
    rm -f $rootPath/helm-push.tar
fi

echo_task "add tests users and administrator into ldap"
if [[ $skipped -ne 1 ]]; then
    ldapadd -x -H ldap://$ldapDomain:389 -D "cn=admin,$ldapBindDN" -w $ldapRootPW -f $rootPath/tests/dex-example-config-ldap.ldif
    ldapadd -x -H ldap://$ldapDomain:389 -D "cn=admin,$ldapBindDN" -w $ldapRootPW -f $templatePath/cluster-admin.ldif
fi

#echo_task ""
#if [[ $skipped -ne 1 ]]; then
#fi

echo -e "\n\nAll tasks done!"
if [[ $skipFirstN -eq 0 && $skipLastFrom -eq 0 ]]; then
    echo "Spend seconds: $((`date +%s`-startTime))"
fi
echo "Next:"
echo -e "\tEnsure your cluster file is under $clusterPath, then run:"
echo -e "\t$scriptPath/pre_deploy_stage_1.sh <YOUR_CLUSTER_NAME>"
