#!/bin/bash

usage(){
	echo "$0 [-h] [-f /path/to/etcd/openssl.conf] [-ca /path/to/etcd/ca.pem] [-ck /path/to/etcd/ca-key.pem] <NEW-NODE-HOSTNAME>"
	echo ""
	echo "-f: default to /etc/ssl/etcd/openssl.conf"
	echo "-ca: default to /etc/ssl/etcd/ssl/ca.pem"
	echo "-ck: default to /etc/ssl/etcd/ssl/ca-key.pem"
	exit
}

host=""
CONFIG=/etc/ssl/etcd/openssl.conf
CA=/etc/ssl/etcd/ssl/ca.pem
CAKEY=/etc/ssl/etcd/ssl/ca-key.pem

while [[ ! -z $1 ]]; do
	case $1 in
		"-f") CONFIG=$2; shift 2;;
		"-ca") CA=$2; shift 2;;
		"-ck") CAKEY=$2; shift 2;;
		"-h") usage; shift;;
		*) host=$1; shift;;
	esac
done

if [[ ! -f $CONFIG ]]; then
    echo "etcd openssl.conf not found"
    usage
fi

if [[ ! -f $CA ]]; then
    echo "etcd ca.pem not found"
    usage
fi

if [[ ! -f $CAKEY ]]; then
    echo "etcd ca-key.pem not found"
    usage
fi

if [[ -z $host ]]; then
	echo "hostname not assigned"
    usage
fi

# from: kubespray/roles/etcd/templates/make-ssl-etcd.sh.j2 
openssl genrsa -out node-${host}-key.pem 2048 > /dev/null 2>&1
openssl req -new -key node-${host}-key.pem -out node-${host}.csr -subj "/CN=etcd-node-${host}" > /dev/null 2>&1
openssl x509 -req -in node-${host}.csr -CA ${CA} -CAkey ${CAKEY} -CAcreateserial -out node-${host}.pem -days 36500 -extensions ssl_client -extfile ${CONFIG} > /dev/null 2>&1

rm ./node-${host}.csr
