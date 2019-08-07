skipFirstN=0  # note: set -1 to skip all tasks to check taskId
skipLastFrom=0
notSkip=()    # note: work with skipFirstN=-1


rootPath="$(cd `dirname $0`; cd .. ; pwd)"
source $rootPath/scripts/utils.sh

install_deployer_check
if [[ $checkFailed -eq 1 ]]; then
    exit 1
fi

startTime=`date +%s`

if [[ -z $infraIP ]]; then
    echo "IP check failed..."
    exit
fi
echo "IP check pass..."

source $scriptPath/utils.sh

echo_task "express tar packages"
if [[ $skipped -ne 1 ]]; then
    pushd $rootPath
    num=`ls *.tar | wc -l`
    idx=1
    for i in `ls *.tar`; do
        echo "$idx/$num: $i"
        tar xf $i
	rm -f $i
	idx=$((idx+1))
    done
    popd
fi

echo_task "add infra domain into /etc/hosts"
if [[ $skipped -ne 1 ]]; then
    for i in "$pkgRepoHost" "$imgRepo" "$chartRepoHost" ; do
        grep -q $i /etc/hosts
        if [[ $? -ne 0 ]]; then
            echo "$infraIP  $i" >> /etc/hosts
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
    pushd $imgPath
    docker load < onecache.tar
    rm -f onecache.tar
    popd
fi

echo_task "start local repo"
if [[ $skipped -ne 1 ]]; then
    bash $scriptPath/start_repo.sh
    for i in {5..1}; do
	echo "Wait $i second for local repo up..."
	sleep 1
    done
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
    docker load < $imgPath/chartmuseum.latest.tar
    bash $scriptPath/start_chartmuseum.sh
    rm $imgPath/chartmuseum.latest.tar
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
    sed -i "s/hostname: reg.mydomain.com/hostname: $imgRepo/" harbor.yml
    ./install.sh
    rm -f harbor.v1.8.1.tar.gz
    popd
    up=0
    for i in {1..20}; do
	docker login -uadmin -p$harborAdminPw $imgRepo
	if [[ $? -eq 0 ]]; then
	    up=1
	    break
	fi
	echo "Failed to login harbor, wait 3 second to verify again..."
	sleep 3
    done
    if [[ $up -eq 0 ]]; then
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
    for i in {5..1}; do
	    echo "Wait $i second for local repo up..."
        sleep 1
    done
fi

echo_task "install helm push plugin"
if [[ $skipped -ne 1 ]]; then
    curl $pkgRepo/helm-push.tar -o $rootPath/helm-push.tar
    tar xf $rootPath/helm-push.tar -C $rootPath
    curl $pkgRepo/helm-push_install_plugin.sh -o $rootPath/helm-push/scripts/install_plugin.sh
    helm plugin install $rootPath/helm-push
    rm -f $rootPath/helm-push.tar
fi

#echo_task ""
#if [[ $skipped -ne 1 ]]; then
#fi

echo -e "\n\nAll tasks done!"
if [[ $skipFirstN -eq 0 && $skipLastFrom -eq 0 ]]; then
    echo "Spend seconds: $((`date +%s`-startTime))"
fi
echo "Next to run $scriptPath/pre_deploy.sh"
