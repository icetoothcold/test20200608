apiserver=127.0.0.1
loginapp=http://loginapp-proxy.example.com
loginappIP=127.0.0.1
ns=kube-system
user=admin
pass=password
resp=`curl -s --resolve loginapp-proxy.example.com:80:$loginappIP -X POST $loginapp/get-token -d "{\"login\":\"$user\",\"password\":\"$pass\"}" -H "Content-Type: application/json" | python -mjson.tool`
echo -e "Get-token repsonse: $resp\n"
token=`echo $resp | awk -F'"' '/id-token/{print $4}'`
curl -H "Authorization: Bearer $token" -k https://$apiserver:6443/api/v1/namespaces/$ns/pods
