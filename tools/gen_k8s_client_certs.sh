#!/bin/bash
# Refer: https://gist.github.com/henning/2dda0b704426c66e78e355703a8dc177

CLUSTERNAME=cluster.local
NAMESPACE=
USERNAME=
GROUPNAME=
ROLENAME=

CERTIFICATE_NAME=$USERNAME.$NAMESPACE
CSR_FILE=$USERNAME.csr
CRT_FILE=$USERNAME.crt
KEY_FILE=$USERNAME.key

openssl genrsa -out $KEY_FILE 2048

openssl req -new -key $KEY_FILE -out $CSR_FILE -subj "/CN=$USERNAME/O=$GROUPNAME"

# To make it repeatable
kubectl get csr $CERTIFICATE_NAME && kubectl delete csr $CERTIFICATE_NAME
kubectl get role $ROLENAME && kubectl delete role $ROLENAME
kubectl get rolebinding $ROLENAME && kubectl delete rolebinding $ROLENAME

cat <<EOF | kubectl create -f -
apiVersion: certificates.k8s.io/v1beta1
kind: CertificateSigningRequest
metadata:
  name: $CERTIFICATE_NAME 
spec:
  groups:
  - system:authenticated
  request: $(cat $CSR_FILE | base64 | tr -d '\n')
  usages:
  - digital signature
  - key encipherment
  - client auth
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: $ROLENAME
  namespace: $NAMESPACE
rules:
- apiGroups: ["", "extensions", "apps"]
  resources: ["deployments", "replicasets", "pods"]
  verbs: ["*"]  # get", "list", "watch", "create", "update", "patch", "delete"] # You can also use ["*"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: $ROLENAME
  namespace: $NAMESPACE
subjects:
- kind: User
  name: $USERNAME
  #apiGroup: ""
  apiGroup: "rbac.authorization.k8s.io"
roleRef:
  kind: Role
  name: $ROLENAME
  #apiGroup: ""
  apiGroup: "rbac.authorization.k8s.io"
EOF

kubectl certificate approve $CERTIFICATE_NAME
kubectl get csr $CERTIFICATE_NAME -o jsonpath='{.status.certificate}'  | base64 -d > $CRT_FILE

CONFIG_TML=./client.config.tml.j2
cat ~/.kube/config | grep -v client > $CONFIG_TML
echo "    client-certificate-data: {{ clientCrt }}" >> $CONFIG_TML
echo "    client-key-data: {{ clientKey }}" >> $CONFIG_TML
CONFIG_DATA=./config.data.tmp
echo -n "clientCrt: " > $CONFIG_DATA
cat $CRT_FILE | base64 -w0 >> $CONFIG_DATA
echo "" >> $CONFIG_DATA
echo -n "clientKey: " >> $CONFIG_DATA
cat $KEY_FILE | base64 -w0 >> $CONFIG_DATA
jinja2 $CONFIG_TML $CONFIG_DATA --format=yaml > client.config

rm -f $CONFIG_TML $CONFIG_DATA $CSR_FILE

exit

kubectl config set-credentials $USERNAME \
  --client-certificate=$(pwd)/$CRT_FILE \
  --client-key=$(pwd)/$KEY_FILE

kubectl config set-context $USERNAME-context --cluster=$CLUSTERNAME --namespace=$NAMESPACE --user=$USERNAME
