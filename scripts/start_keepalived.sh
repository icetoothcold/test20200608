rootPath="$(cd `dirname $0`; cd ..; pwd)"
source $rootPath/scripts/utils.sh

all_ips=`get_infra_ips ${haproxyHosts}`

docker rm -f keepalived-vip
docker run -d --name keepalived-vip \
    -v $templatePath/keepalived.conf.tml:/config/keepalived.conf.temp \
    -v $scriptPath/repo_check.sh:/repo_check.sh \
    -v $scriptPath/keepalived_notify_harbor.sh:/notify.sh \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e ALL_IPS="$all_ips" \
    -e VIPS="$imageRepoVIP $ldapVIP" \
    -e INTF="$vipInterface" \
    -e AD_INT="$keepalivedAdvertIntv" \
    -e VRID="$keepalivedVRID" \
    -e NOTIFY_SCRIPT="/notify.sh" \
    --restart 'always' \
    --cap-add NET_ADMIN \
    --network host \
    $imgRepo/library/keepalived-vip:$keepalivedTag
