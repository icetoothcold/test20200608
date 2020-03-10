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
    for i in "$pkgRepoHost" "$imgRepo" "$ldapDomain"; do
        grep -q $i /etc/hosts
        if [[ $? -ne 0 ]]; then
            echo "$myIP  $i" >> /etc/hosts
        fi
    done
    if [[ $harborWithChartmusuem != "true" ]]; then
        grep -q $chartRepoHost /etc/hosts
        if [[ $? -ne 0 ]]; then
            echo "$myIP  $chartRepoHost" >> /etc/hosts
        fi
    fi
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
    yum localinstall -y audit* checkpolicy* containerd.io* container-selinux* docker-ce* libcgroup* libselinux* libsemanage* libsepol* policycoreutils-python-2.5-29.el7_6.1.x86_64 python-IPy* selinux-policy* setools-libs* pcre-devel*
    if [[ $? -ne 0 ]]; then
        "Sorry, package conflicts is out of alcor installing, try to handle it manually :("
    fi
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
    if [[ $harborWithChartmusuem != "true" ]]; then
        image=`ls $imgPath | grep chartmuseum`
        docker load < $imgPath/$image
        docker tag chartmuseum/chartmuseum $imgRepo/chartmuseum/chartmuseum
        bash $scriptPath/start_chartmuseum.sh
    else
        echo "Skipped, since seperate chartmuseum is disabled"
    fi
fi

echo_task "yum install docker-compose"
if [[ $skipped -ne 1 ]]; then
    yum -y install docker-compose
fi

echo_task "install harbor"
if [[ $skipped -ne 1 ]]; then
    tgzFile=harbor-offline-installer-${harborVersion}.tgz
    if [[ -f $rpmsPath/$tgzFile ]]; then
        cp $rpmsPath/$tgzFile $rootPath/$tgzFile
    else
        curl $pkgRepo/$tgzFile -o $rootPath/$tgzFile
    fi
    tar xf $rootPath/$tgzFile -C $rootPath
    rm -f $rootPath/$tgzFile
    docker load < $imgPath/postgres.9.6.tar
    pushd $rootPath/harbor
    sed -i -e "s/^hostname:.*/hostname: $imgRepo/" \
           -e "s/^harbor_admin_password:.*/harbor_admin_password: $harborAdminPw/" \
           -e "s#^data_volume:.*#data_volume: $harborDataVolume#" harbor.yml
    docker load < harbor.${harborVersion}.tar.gz
    withOpts=""
    if [[ $harborWithClair == "true" ]]; then
        withOpts="--with-clair"
    fi
    if [[ $harborWithChartmusuem == "true" ]]; then
        withOpts="$withOpts --with-chartmuseum"
    fi
    ./prepare $withOpts
    # disable XSRF
    sed -i 's/^EnableXSRF =.*/EnableXSRF = false/g' ./common/config/core/app.conf
    # replace postgresql with clair-db in clair depends_on
    if [[ `echo $withOpts | grep -c "clair"` -ne 0 ]]; then
        clairFirstLine=`awk '/^  [^ ]/{print NR,$1}' docker-compose.yml | awk '/ clair:/{print $1}'`
        clairIndex=`awk '/^  [^ ]/{print NR,$1}' docker-compose.yml | awk '/ clair:/{print NR}'`
        clairLastLine=$((`awk '/^  [^ ]/{print NR,$1}' docker-compose.yml | awk "{if(NR==$((clairIndex+1)))print $1}" | cut -d ' ' -f 1`-1))
        # modify clair depends_on
        sed -i "$clairFirstLine,${clairLastLine}s/postgresql/clair-db/" docker-compose.yml
        # insert clair-db
        sed -i "${clairLastLine}a\ \ clair-db:\n    networks:\n      - harbor-clair\n    container_name: clair-db\n    image: postgres:9.6\n    restart: always\n    cap_drop:\n      - ALL\n    cap_add:\n      - CHOWN\n      - DAC_OVERRIDE\n      - SETGID\n      - SETUID\n    user: 999:999\n    volumes:\n      - $harborDataVolume/clair_db:/var/lib/postgresql/data:z\n    dns_search: .\n    environment:\n      - POSTGRES_USER=postgres\n      - POSTGRES_PASSWORD=root123" docker-compose.yml
        cp -f $templatePath/harbor_with_clair_db/config.yaml common/config/clair/config.yaml
        pushd $imgPath > /dev/null
            docker load < postgres.9.6.tar
        popd > /dev/null
        mkdir $harborDataVolume/clair_db
        chown `ls -dl $harborDataVolume/database | awk '{print $3":"$4}'` $harborDataVolume/clair_db
    fi
    # insert extra_hosts for ldap for harbor-core
    coreLine=`awk '/^  core:/{print NR}' docker-compose.yml`
    sed -i "${coreLine}a\ \ \ \ extra_hosts:\n      - $ldapDomain:$ldapVIP" docker-compose.yml
    docker-compose up -d
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
    ln -sfT /usr/local/bin/pip3.6 /usr/bin/pip3.6
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
    if [[ ! -f ~/.ssh/id_rsa.pub || ! -f ~/.ssh/id_rsa || `diff <( ssh-keygen -yef ~/.ssh/id_rsa.pub ) <( ssh-keygen -yef ~/.ssh/id_rsa ) | wc -l` -ne 0 ]]; then
        ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
    else
        echo -ne "\nssh rsa key already exists, nothing to do..."
    fi
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

echo_task "add tests users and adminitrator into ldap"
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
echo -e "\t(optional) to upgrade to HA, deploy a HA peer run:"
echo -e "\t    $scriptPath/upgrade_ha_deployers.sh\n"
echo -e "\tEnsure your cluster file is under $clusterPath, then run:"
echo -e "\t$scriptPath/pre_deploy_stage_1.sh <YOUR_CLUSTER_NAME>"
