rpmsPath=$rootPath/rpms_and_files
imgPath=$rootPath/images
scriptPath=$rootPath/scripts
chartPath=$rootPath/charts
versionPath=$rootPath/versions
inventoryPath=$rootPath/kubespray/inventory
clusterPath=$rootPath/clusters
templatePath=$rootPath/templates


myIP=`cat $rootPath/infra.yml | awk -F'"' '/myIP/{print $2}'`
peerIP=`cat $rootPath/infra.yml | awk -F'"' '/peerIP/{print $2}'`
peerRootPW=`cat $rootPath/infra.yml | awk -F'"' '/peerRootPW/{print $2}'`

haproxyHosts=`cat $rootPath/infra.yml | awk -F'"' '/haproxyHosts/{print $2}'`
vipInterface=`cat $rootPath/infra.yml | awk -F'"' '/vipInterface/{print $2}'`
keepalivedAdvertIntv=`cat $rootPath/infra.yml | awk -F'"' '/keepalivedAdvertIntv/{print $2}'`
keepalivedVRID=`cat $rootPath/infra.yml | awk -F'"' '/keepalivedVRID/{print $2}'`
keepalivedTag=`cat $rootPath/infra.yml | awk -F'"' '/keepalivedTag/{print $2}'`

imgRepo=`cat $rootPath/infra.yml | awk -F'"' '/^imageRepo:/{print $2}'`
imageRepoVIP=`for i in $(cat $rootPath/infra.yml | awk -F'"' '/infraVIPs/{print $2}'); do echo $i | awk -F ':' '/imageRepo/{print $2}'; done`
imgRepoHosts=`cat $rootPath/infra.yml | awk -F'"' '/imgRepoHosts/{print $2}'`

pkgRepo=`cat $rootPath/infra.yml | awk -F'"' '/^pkgRepo:/{print $2}'`
pkgRepoHost=`echo $pkgRepo | cut -d '/' -f 3 | cut -d ':' -f 1`
pkgRepoPort=`echo $pkgRepo | cut -d ':' -f 3`
pkgRepoVIP=`for i in $(cat $rootPath/infra.yml | awk -F'"' '/infraVIPs/{print $2}'); do echo $i | awk -F ':' '/pkgRepo/{print $2}'; done`
pkgRepoHosts=`cat $rootPath/infra.yml | awk -F'"' '/pkgRepoHosts/{print $2}'`
pypiPort=`cat $rootPath/infra.yml | awk '/pypiPort/{print $2}'`

chartRepo=`cat $rootPath/infra.yml | awk -F'"' '/^chartRepo:/{print $2}'`
chartRepoHost=`echo $chartRepo | cut -d '/' -f 3 | cut -d ':' -f 1`
chartRepoPort=`echo $chartRepo | cut -d ':' -f 3`
chartRepoVIP=`for i in $(cat $rootPath/infra.yml | awk -F'"' '/infraVIPs/{print $2}'); do echo $i | awk -F ':' '/chartRepo/{print $2}'; done`
localInfraChartRepo=`cat $rootPath/infra.yml | awk -F'"' '/localInfraChartRepo/{print $2}'`

harborAdminPw=`cat $rootPath/infra.yml | awk -F'"' '/harborAdminPw/{print $2}'`
harborGcCron=`cat $rootPath/infra.yml | awk -F'"' '/harborGcCron/{print $2}'`
harborShareVolume=`cat $rootPath/infra.yml | awk -F'"' '/harborShareVolume/{print $2}'`

ldapOrgName=`cat $rootPath/infra.yml | awk -F'"' '/ldapOrgName/{print $2}'`
ldapDomain=`cat $rootPath/infra.yml | awk -F'"' '/ldapDomain/{print $2}'`
ldapRootPW=`cat $rootPath/infra.yml | awk -F'"' '/ldapRootPW/{print $2}'`
ldapBindDN=`cat $rootPath/infra.yml | awk -F'"' '/ldapBindDN/{print $2}'`
ldapVIP=`for i in $(cat $rootPath/infra.yml | awk -F'"' '/infraVIPs/{print $2}'); do echo $i | awk -F ':' '/ldap/{print $2}'; done`
ldapHABackendPort=`cat $rootPath/infra.yml | awk '/ldapHABackendPort/{print $2}'`
ldapHosts=`cat $rootPath/infra.yml | awk -F'"' '/ldapHosts/{print $2}'`


tasksNum=`grep -c '^echo_task ' $0`
taskId=0
skipped=0  # necessary init
checkFailed=0
parseFailed=0
kubeVersion=""
force=""
declare -a hostIPs

CMD_DISABLE_FIREWALLD="systemctl stop firewalld; systemctl disable firewalld"
CMD_BACKUP_YUM_REPOS="mkdir /etc/yum.repos.d/bak; mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak"
CMD_BACKUP_IPTABLES="touch /etc/sysconfig/iptables; touch /etc/sysconfig/ip6tables; ts=\$(date +%s); cp /etc/sysconfig/iptables /etc/sysconfig/iptables-\$ts; cp /etc/sysconfig/ip6tables /etc/sysconfig/ip6tables-\$ts; iptables-save >/etc/sysconfig/iptables; ip6tables-save >/etc/sysconfig/ip6tables"
CMD_SYSTEMCTL_RESTART_DOCKER="systemctl daemon-reload; systemctl enable docker; systemctl restart docker"
CMD_CONFIG_PIP="pip3.6 install -i http://$pkgRepoHost:$pypiPort/simple --trusted-host $pkgRepoHost pip -U; ln -s /usr/local/bin/pip3.6 /usr/bin/pip3.6; pip3.6 config set global.index-url http://$pkgRepoHost:$pypiPort/simple; pip3.6 config set global.trusted-host $pkgRepoHost"
CMD_GET_EXTRACT_HARBOR="cd $rootPath; curl $pkgRepo/harbor-offline-installer-v1.8.1.tgz -o harbor-offline-installer-v1.8.1.tgz; tar xf harbor-offline-installer-v1.8.1.tgz; rm -f harbor-offline-installer-v1.8.1.tgz"
CMD_MODIFY_HARBOR_HOST_PSWD="sed -i -e 's#^hostname:.*#hostname: $imgRepo#' -e 's/^harbor_admin_password:.*/harbor_admin_password: $harborAdminPw/' harbor.yml"

# call script should define taskId, skipped, tasksNum, skipFirstN, skipLastFrom, notSkip
function echo_task
{
    taskId=$((taskId+1))
    fmt="\n\n"
    if [[ $skipped -eq 1 ]]; then
        fmt=""
    fi
    echo -en "${fmt}task $taskId/$tasksNum: $1"
    skipped=0
    if [[ $taskId -le $skipFirstN || $skipFirstN -eq -1 ]]; then
        skipped=1
        for i in ${notSkip[@]}; do
            if [[ $i -eq $taskId ]]; then
                skipped=0
            fi
        done
        if [[ $skipped -eq 1 ]];then
            echo "...skipped"
        fi
    elif [[ $skipLastFrom -gt 0 && $taskId -ge $skipLastFrom ]]; then
        skipped=1
        echo "...skipped"
    else
        echo ""
    fi
}


function install_deployer_check
{
    if [[ ! -f $rpmsPath.tar && ! -d $rpmsPath ]]; then
        echo "One of the following files or directory not exists, failed to install deployer"
        echo -e "\t$rpmsPath.tar"
        echo -e "\t$rpmsPath"
        checkFailed=1
    fi
    if [[ ! -d $imgPath ]]; then
        echo "One of the following files or directory not exists, failed to install deployer"
        echo -e "\t$imgPath"
        checkFailed=1
    fi
    if [[ ! -f $scriptPath.tar && ! -d $scriptPath ]]; then
        echo "One of the following files or directory not exists, failed to install deployer"
        echo -e "\t$scriptPath.tar"
        echo -e "\t$scriptPath"
        checkFailed=1
    fi
    if [[ ! -f $chartPath.tar && ! -d $chartPath ]]; then
        echo "One of the following files or directory not exists, failed to install deployer"
        echo -e "\t$chartPath"
        echo -e "\t$chartPath.tar"
        checkFailed=1
    fi
    echo "Materials check pass..."
}


function extract_tar_packages
{
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
}


function pre_deploy_check
{
    # note: use `python3 contrib/inventory_builder/inventory.py help` to check inventory help
    # idea: do this in container
    if [[ -z $1 || $1 == "-h" ]]; then
        echo "bash $0 [-h] <YOUR_CLUSTER_FILE_NAME>"
        echo -e "\t-h: show this help"
        echo -e "\tYour cluster file should be under $clusterPath, and ends with .yml"
        echo -e "\tYour cluster file should be a yaml file, and it's format should be like:"
        echo -e "\t\tclusterName: YOUR_CLUSTER_NAME"
        echo -e "\t\tIP1: IP1_PASSWORKD"
        echo -e "\t\tIP2: IP2_PASSWORKD"
        echo -e "\t\t..."
        echo -e "\t\tkubeVersion: VERSION , like v1.15.0"
        echo -e "\t\tforce: false , or true"
        echo -e "\tNOTE: 1)don't use '\"' or \"'\" to enclose string"
        echo -e "\t      2)set force to true to override known cluster and deployer a new one"
        checkFailed=1
    fi
}


function parse_cluster_file
{
    kubeVersion=`cat $clusterFile | awk '/kubeVersion/{print $2}'`
    kubeVersion=`ls $versionPath | grep $kubeVersion`
    if [[ $kubeVersion == "" ]]; then
        echo "Version not found, or not supported"
        echo -e "Chose one of the following version:\n`ls $versionPath | egrep -v \"(common)\"`"
        parseFailed=1
    fi
    if [[ `ls $versionPath | grep -c $kubeVersion` -ne 1 ]]; then
        echo "Version can't determine"
        echo -e "Chose one of the following version:\n`ls $versionPath | egrep -v \"(common)\"`"
        parseFailed=1
    fi
    sed -i "s/kubeVersion.*/kubeVersion: $kubeVersion/" $clusterFile
    force=`cat $clusterFile | awk '/force/{print $2}'`
    if [[ $force != "true" ]]; then
        force="false"
    fi
    for ip in `awk -F':' '/^[^#]/{print $1}' $clusterFile`; do
        ipcalc -cs4 $ip
        if [[ $? -eq 0 ]]; then
            hostIPs+=($ip)
        fi
    done
    if [[ "${hostIPs[@]}" == "" ]]; then
        echo "No host IPs found"
        parseFailed=1
    fi
}


function post_deploy_check
{
    if [[ -z $1 || $1 == "-h" ]]; then
        echo "bash $0 [-h] <YOUR_CLUSTER_NAME>"
        echo -e "\t-h: show this help"
        echo -e "\tYour cluster file should be under $clusterPath, and ends with .yml"
        checkFailed=1
    fi
    if [[ ! -d $inventoryPath/$1 ]]; then
        echo "Your cluster name cannot be found under $inventoryPath"
        echo "Seems not deployed yet!"
        checkFailed=1
    fi
}


function verify_repo_up
{
    up=0
    for i in {1..20}; do
        if [[ $1 == "harbor" ]]; then
            if [[ -z $2 ]]; then
                docker login -uadmin -p$harborAdminPw $imgRepo 2>/dev/null 1>/dev/null
            else
                curl -sf http://$2/api/health -H  "accept: application/json" | grep 'components' -B 1 | grep -q '"healthy"'
            fi
        elif [[ $1 == "repo" ]]; then
            curl -sf $pkgRepo/private.repo 2>/dev/null 1>/dev/null
        elif [[ $1 == "ldap" ]]; then
            if [[ -z $2 ]]; then
                ldapsearch -x -H ldap://$ldapDomain:389 -b $ldapBindDN -D "cn=admin,$ldapBindDN" -w $ldapRootPW 2>/dev/null 1>/dev/null
            else
                ldapsearch -x -H ldap://$2 -b $ldapBindDN -D "cn=admin,$ldapBindDN" -w $ldapRootPW 2>/dev/null 1>/dev/null
            fi
        elif [[ $1 == "vip" ]]; then
            ping -c3 -w3 $2 2>/dev/null 1>/dev/null
        fi
        if [[ $? -eq 0 ]]; then
            up=1
            break
        fi
        sleep 3
    done
    echo $up
}


function get_master_ips_string
{
    # return a string, not an array, but it's ok for for-loop
    python3 -c "import yaml; all=yaml.safe_load(open('$inventoryPath/$1/hosts.yml'))['all']; print(' '.join([all['hosts'][host]['ip'] for host in all['hosts'] if host in all['children']['kube-master']['hosts']]))"
}


function diff_and_cp
{
    diff -q $1 $2
    if [[ $? -ne 0 ]]; then
        cp $1 $2
    fi
}


# Usage, e.g.:
#   for i in `walk_infra_hosts "${imgRepoHosts[@]}"`; do
#       host=`echo $i | cut -d ':' -f 1`
#       rootPw=`echo $i | cut -d ':' -f 2`
#       echo "host: $host, root password: $rootPw"
#   done
function walk_infra_hosts
{
    host_ips=`for i in $(echo $1); do echo $i | cut -d ':' -f 1 ; done | xargs -I{} echo {} | sed 's/,/ /'`
    ipPws=""
    lastIpIdx=0
    for j in $(echo $1); do
        rootPw=`echo $j | awk -F':' '{print $2}'`
        ipIdx=0
        for ip in ${host_ips[@]}; do
            ipIdx=$((ipIdx+1))
            if [[ $ipIdx -le $lastIpIdx ]]; then
                continue
            fi
            if [[ `echo $j | egrep -c "$ip(,|:)"` -eq 1 ]]; then
                ipPws="$ip:$rootPw ${ipPws[@]}"
                lastIpIdx=$((lastIpIdx+1))
            fi
        done
    done
    echo ${ipPws[@]}
}


function get_infra_ips
{
    ips=""
    for i in `walk_infra_hosts "$1"`; do
        ip=`echo $i | cut -d ':' -f 1`
        if [[ `echo ${ips[@]} | grep -c $ip` -eq 0 ]]; then
            ips="${ips[@]} $ip"
        fi
    done
    echo ${ips[@]}
}


function ssh_authorize
{
    sshpass -p foo ssh -o StrictHostKeyChecking=no root@$1 "exit"
    if [[ $? -ne 0 ]]; then
        ssh-keyscan $1 >> ~/.ssh/known_hosts
        sshpass -p $2 ssh-copy-id -f root@$1
    fi
}


# insert_hosts $nodeIps hostname ip
function insert_hosts
{
    for ip in $1; do
        if [[ `ssh root@$ip "grep -c $2 /etc/hosts"` -eq 0 ]]; then
            ssh root@$ip "echo '$3  $2' >> /etc/hosts"
        fi
    done
}


function add_pkg_repo_tmp_vip
{
    dev=`ip r get 8.8.8.8 | awk '/dev/{print $5}'`
    for vip in "$pkgRepoVIP" "$chartRepoVIP"; do
        ip a add dev $dev $vip/32
    done
}


function get_all_infra_ips
{
    get_infra_ips "${imgRepoHosts[@]} ${ldapHosts[@]} ${haproxyHosts[@]} ${pkgRepoHosts[@]}"
}
