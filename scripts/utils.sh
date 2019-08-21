rpmsPath=$rootPath/rpms_and_files
imgPath=$rootPath/images
scriptPath=$rootPath/scripts
chartPath=$rootPath/charts
versionPath=$rootPath/versions
inventoryPath=$rootPath/kubespray/inventory
clusterPath=$rootPath/clusters


myIP=`cat $rootPath/infra.yml | awk -F'"' '/myIP/{print $2}'`
peerIP=`cat $rootPath/infra.yml | awk -F'"' '/peerIP/{print $2}'`
peerRootPW=`cat $rootPath/infra.yml | awk -F'"' '/peerRootPW/{print $2}'`
imgRepo=`cat $rootPath/infra.yml | awk -F'"' '/imageRepo:/{print $2}'`
imageRepoVIP=`cat $rootPath/infra.yml | awk -F'"' '/imageRepoVIP/{print $2}'`
pkgRepo=`cat $rootPath/infra.yml | awk -F'"' '/pkgRepo:/{print $2}'`
pkgRepoHost=`echo $pkgRepo | cut -d '/' -f 3 | cut -d ':' -f 1`
pkgRepoPort=`echo $pkgRepo | cut -d ':' -f 3`
pkgRepoVIP=`cat $rootPath/infra.yml | awk -F'"' '/pkgRepoVIP/{print $2}'`
chartRepo=`cat $rootPath/infra.yml | awk -F'"' '/chartRepo:/{print $2}'`
chartRepoHost=`echo $chartRepo | cut -d '/' -f 3 | cut -d ':' -f 1`
chartRepoPort=`echo $chartRepo | cut -d ':' -f 3`
chartRepoVIP=`cat $rootPath/infra.yml | awk -F'"' '/chartRepoVIP/{print $2}'`
harborAdminPw=`cat $rootPath/infra.yml | awk -F'"' '/harborAdminPw/{print $2}'`
localInfraChartRepo=`cat $rootPath/infra.yml | awk -F'"' '/localInfraChartRepo/{print $2}'`
pypiPort=`cat $rootPath/infra.yml | awk '/pypiPort/{print $2}'`
ldapOrgName=`cat $rootPath/infra.yml | awk -F'"' '/ldapOrgName/{print $2}'`
ldapDomain=`cat $rootPath/infra.yml | awk -F'"' '/ldapDomain/{print $2}'`
ldapRootPW=`cat $rootPath/infra.yml | awk -F'"' '/ldapRootPW/{print $2}'`
ldapBindDN=`cat $rootPath/infra.yml | awk -F'"' '/ldapBindDN/{print $2}'`
ldapVIP=`cat $rootPath/infra.yml | awk -F'"' '/ldapVIP/{print $2}'`


tasksNum=`grep -c '^echo_task ' $0`
taskId=0
skipped=0  # necessary init
checkFailed=0
parseFailed=0
kubeVersion=""
force=""
declare -a hostIPs


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
            docker login -uadmin -p$harborAdminPw $imgRepo 2>1 1>/dev/null
        elif [[ $1 == "repo" ]]; then
            curl -sf $pkgRepo/private.repo 2>1 1>/dev/null
        elif [[ $1 == "ldap" ]]; then
            ldapsearch -x -H ldap://$ldapDomain:389 -b $ldapBindDN -D "cn=admin,$ldapBindDN" -w $ldapRootPW 2>1 1>/dev/null
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
