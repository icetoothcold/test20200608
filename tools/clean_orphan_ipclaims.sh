del=""
if [[ ! -z $1 && $1 == "-x" ]]; then
    del="true"
fi

for i in `kubectl get ipc --all-namespaces | awk '{if(NR>1)print $1"_"$2}'`; do
    ns=`echo $i | cut -d '_' -f 1`
    ipcName=`echo $i | cut -d '_' -f 2`
    owner=`kubectl -n $ns get ipc $ipcName -o jsonpath='{.metadata.ownerReferences[0].name}'`
    ip=`kubectl -n $ns get ipc $ipcName -o template='{{.status.IP}}'`
    echo -n "Found ipc $ipcName ip $ip in namespace $ns, with owner $owner ... "
    # only consider kind unit
    podName=`kubectl -n $ns get unit $owner -o template='{{.spec.podtemplate.metadata.name}}'`
    kubectl -n $ns pod $podName -o yaml | grep -q $ip
    if [[ $? -ne 0 ]]; then
        echo -n "but not in use"
        if [[ -z $del ]]; then
            echo ", will not delete it without '-x'"
        else
            echo ", delete it since '-x' set"
            kubectl -n $ns delete ipc $ipcName
        fi
    fi
done
