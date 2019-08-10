#!/bin/bash
#
# refer https://github.com/dexidp/dex/blob/master/examples/k8s/gencert.sh

if [[ -z $1 ]]; then
    echo "No clusterName assigned"
    exit 1
fi

rootPath="$(cd `dirname $0`; cd ..; pwd)"
clusterName=$1
outputPath=$rootPath/clusters/${1}_dex_ca
gen=1

if [[ ! -d $outputPath ]]; then
    mkdir -p $outputPath
elif [[ ! -f $outputPath/cert.pem || ! -f $outputPath/key.pem || -f $outputPath/ca.pem ]]; then
    rm -rf $outputPath/*
else
    openssl verify -CAfile $outputPath/ca.pem $outputPath/cert.pem
    if [[ $? -ne 0 ]]; then
        rm -rf $outputPath/*
    else
        checkInfo=`openssl x509 -text -in $outputPath/cert.pem | awk -F':' '/Issuer/||/DNS/{print $2}'`
        if [[ `echo $checkInfo | grep -c "CN=kube-ca"` -eq 0 || `echo $checkInfo | grep -c "dex.$clusterName.io"` -eq 0 ]]; then
            rm -rf $outputPath/*
        else
            gen=0
        fi
    fi
fi

if [[ $gen -eq 0 ]]; then
    exit
fi

cat << EOF > $outputPath/req.cnf
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name

[req_distinguished_name]

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = dex.$clusterName.io
EOF

openssl genrsa -out $outputPath/ca-key.pem 2048
openssl req -x509 -new -nodes -key $outputPath/ca-key.pem -days 3650 -out $outputPath/ca.pem -subj "/CN=kube-ca"

openssl genrsa -out $outputPath/key.pem 2048
openssl req -new -key $outputPath/key.pem -out $outputPath/csr.pem -subj "/CN=kube-ca" -config $outputPath/req.cnf
openssl x509 -req -in $outputPath/csr.pem -CA $outputPath/ca.pem -CAkey $outputPath/ca-key.pem -CAcreateserial -out $outputPath/cert.pem -days 3650 -extensions v3_req -extfile $outputPath/req.cnf

echo "cert.pem, key.pem, ca.pem are ready in $outputPath"
