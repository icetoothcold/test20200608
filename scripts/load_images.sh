if [[ ${0##*/} == "load_images.sh" ]]; then
    rootPath="$(cd `dirname $0`; cd ..; pwd)"
    source $rootPath/scripts/utils.sh
fi
tmpFile=$rootPath/tmp.`date +%s`

if [[ `verify_repo_up "harbor"` -ne 1 ]]; then
    echo "After 1 min, harbor up detect failed..."
    exit 1
fi

docker login -uadmin -p$harborAdminPw $imgRepo

num=`ls $imgPath | wc -l`
idx=0
for i in `ls $imgPath/*.tar`; do
    refered=`grep $i $imgPath/refer | awk '{print $2" "$3}'`
    if [[ ! -z $refered ]]; then
        referFile=`echo $refered | awk '{print $1}'`
        referKey=`grep $refered | awk '{print $2}'`
        if [[ `grep $referKey $rootPath/$referFile | awk '{print $2}'` == "false" ]]; then
            echo "Skip to load $i, since not used"
            continue
        fi
    fi
    docker load < $i > $tmpFile
    if [[ $? -ne 0 ]]; then
        echo "Failed to load image $imgPath/$i"
        exit 1
    fi
    oldInfo=`awk '{print $3}' $tmpFile`
    echo -n -e "$idx/$num: Retag $oldInfo "

    oldRepo=`echo $oldInfo | cut -d ':' -f 1`
    tag=`echo $oldInfo | cut -d ':' -f 2`
    # level
    # 3: gcr.io/kubernetes-helm/tiller
    # 2: coredns/coredns
    # 1: chartmuseumui
    level=`echo $oldRepo | awk -F"/" '{print NF}'`
    site=`echo $oldRepo | cut -d '/' -f 1`
    proj=`echo $oldRepo | cut -d '/' -f 2-`
    if [[ $level -eq 3 ]]; then
        # docker images | awk '{print $1}' | awk -F"/" '{if(NF>2)print $1}' | sort | uniq -c
        :
    elif [[ $level -eq 1 ]]; then
        proj="library/$site"
    elif [[ `echo $site | grep -c "\."` -ne 0 ]]; then
        proj=`echo $site | sed 's/\./_/g'`"/"$proj
    else
        proj="$site/$proj"
    fi
    newImage="$imgRepo/$proj:$tag"
    echo " --> $newImage"

    docker tag $oldInfo $newImage
    docker push $newImage
    if [[ $? -ne 0 ]]; then
        projName=`echo $proj | cut -d '/' -f 1`
        curl --retry 10 --retry-delay 3 --retry-max-time 30 -u "admin:$harborAdminPw" -X POST http://$imgRepo/api/projects -H "accept: application/json" -H "Content-Type: application/json" -d "{\"project_name\": \"$projName\", \"metadata\": { \"public\": \"true\" }}"
        if [[ $? -ne 0 ]]; then
            echo "Failed to create project $projName in harbor"
            exit 1
        fi
        sleep 1
        docker push $newImage
        if [[ $? -ne 0 ]]; then
            echo "Failed to push image $newImage into harbor"
            exit 1
        fi
    fi
    docker rmi $oldInfo $newImage
    rm -f $imgPath/$i
    idx=$((idx+1))
done

rm -f $tmpFile
