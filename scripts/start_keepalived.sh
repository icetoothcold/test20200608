rootPath="$(cd `dirname $0`; cd ..; pwd)"
source $rootPath/scripts/utils.sh

all_ips=`get_infra_ips ${haproxyHosts}`

docker rm -f keepalived-vip
docker run -d --name keepalived-vip \
    -v $templatePath/keepalived.conf.tml:/config/keepalived.conf.temp \
    -v $scriptPath/repo_check.sh:/repo_check.sh \
    -e ALL_IPS="$all_ips" \
    -e VIPS="$imageRepoVIP $ldapVIP" \
    -e INTF="$vipInterface" \
    -e AD_INT="$keepalivedAdvertIntv" \
    -e VRID="$keepalivedVRID" \
    --restart 'always' \
    --cap-add NET_ADMIN \
    --network host \
    $imgRepo/library/keepalived-vip:$keepalivedTag
