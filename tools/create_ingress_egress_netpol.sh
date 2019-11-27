#!/usr/bin/bash

function usage
{
    echo "$0 -n NS {-c IPBLOCK | -p NS }"
    echo "-n NS: create networkPolicy for this namespace"
    echo "-c IPBLOCK: ipblock to create with, ipblock must in CIDR format"
    echo "-p NS: peer namespace to create with"
    exit
}

ns=""
ipBlock=""
peerNs=""
while test ! -z $1; do
    case $1 in
        "-h")
            usage
            ;;
        "-n")
            ns=$2
            shift 2
            ;;
        "-c")
            ipBlock=$2
            shift 2
            ;;
        "-p")
            peerNs=$2
            shift 2
            ;;
        *)
            ;;
    esac
done

if [[ $ns == "" ]]; then
    echo "No namespace assigned"
    usage
fi

name=""
if [[ $ipBlock != "" ]]; then
    ipcalc -4 -c $ipBlock
    if [[ $? -ne 0 ]]; then
        echo "invalid ipBlock value, not a CIDR"
        exit 1
    elif [[ `echo $ipBlock | grep -c '/'` -eq 0 ]]; then
        echo "invalid ipBlock value, not a CIDR"
        exit 1
    fi
    name=`echo $ipBlcok | sed 's/\//-/g'`
    policy=`echo -e "    - ipBlock:\n        cidr: ipBlock"`
elif [[ $peerNs != "" ]]; then
    if [[ `kubectl get ns | grep -c "^$peerNs "` -ne 1 ]]; then
        echo "peer namespace not exist"
        exit 1
    fi
    name=$peerNs
    policy="    - namespaceSelector:
        matchLabels:
          name: $peerNs
      podSelector: {}"
else
    echo "No ipBlock or peer namesapce assigned"
    usage
fi

#kubectl -n $ns patch netpol $netpolName --type='json' -p='[{"op":"add","path":"/spec/egress/0/to/0", "value":{"ipBlock":{"cidr":"$ipBlock"}}}]'
#kubectl -n $ns patch netpol $netpolName --type='json' -p='[{"op":"remove","path":"/spec/egress/0/to/0"}]'

cat <<EOF | kubectl create -f -
apiVersion: extensions/v1beta1
kind: NetworkPolicy
metadata:
  name: egress-to-$name
  namespace: $ns
spec:
  egress:
  - to:
$policy
  podSelector: {}
  policyTypes:
  - Egress
EOF

cat <<EOF | kubectl create -f -
apiVersion: extensions/v1beta1
kind: NetworkPolicy
metadata:
  name: ingress-from-$name
  namespace: $ns
spec:
  ingress:
  - from:
$policy
  podSelector: {}
  policyTypes:
  - Ingress
EOF
