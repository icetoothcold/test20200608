ns=$1
apiHost=$2
token=$3

curl -H "Authorization: Bearer $token" -k https://$apiHost:6443/api/v1/namespaces/$ns/pods
