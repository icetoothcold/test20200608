#TODO

ns="null"
user="null"
file="null"
bindingName="null"
roleName="null"
resources=""
extensionsResources=""
appsResources=""
batchResources=""
policyResources=""
getVerbs=""
postVerbs=""
putVerbs=""
patchVerbs=""
deleteVerbs=""

# kubectl api-resources | grep -v false
# NAME                              SHORTNAMES   APIGROUP                       NAMESPACED   KIND
# configmaps                        cm                                          true         ConfigMap
# endpoints                         ep                                          true         Endpoints
# events                            ev                                          true         Event
# limitranges                       limits                                      true         LimitRange
# persistentvolumeclaims            pvc                                         true         PersistentVolumeClaim
# pods                              po                                          true         Pod
# replicationcontrollers            rc                                          true         ReplicationController
# resourcequotas                    quota                                       true         ResourceQuota
# secrets                                                                       true         Secret
# serviceaccounts                   sa                                          true         ServiceAccount
# services                          svc                                         true         Service
# statefulsets                      sts          apps                           true         StatefulSet
# cronjobs                          cj           batch                          true         CronJob
# jobs                                           batch                          true         Job
# daemonsets                        ds           extensions                     true         DaemonSet
# deployments                       deploy       extensions                     true         Deployment
# ingresses                         ing          extensions                     true         Ingress
# networkpolicies                   netpol       extensions                     true         NetworkPolicy
# replicasets                       rs           extensions                     true         ReplicaSet
# poddisruptionbudgets              pdb          policy                         true         PodDisruptionBudget
#
# TODO
#
# bindings                                                                      true         Binding
# podtemplates                                                                  true         PodTemplate
# controllerrevisions                            apps                           true         ControllerRevision
# localsubjectaccessreviews                      authorization.k8s.io           true         LocalSubjectAccessReview
# horizontalpodautoscalers          hpa          autoscaling                    true         HorizontalPodAutoscaler
# leases                                         coordination.k8s.io            true         Lease
# authcodes                                      dex.coreos.com                 true         AuthCode
# authrequests                                   dex.coreos.com                 true         AuthRequest
# connectors                                     dex.coreos.com                 true         Connector
# oauth2clients                                  dex.coreos.com                 true         OAuth2Client
# offlinesessionses                              dex.coreos.com                 true         OfflineSessions
# passwords                                      dex.coreos.com                 true         Password
# refreshtokens                                  dex.coreos.com                 true         RefreshToken
# signingkeies                                   dex.coreos.com                 true         SigningKey
#
# NOT IN PLAN
#
# rolebindings                                   rbac.authorization.k8s.io      true         RoleBinding
# roles                                          rbac.authorization.k8s.io      true         Role

while [[ $* ]]; do
    case $1 in
        "-bind")
            bindingName=$2
            shift 2
        "-cj")
            batchResources="\"cronjobs\", $batchResources"
            shift 1
            ;;
        "-cm")
            resources="\"configmaps\", $resources"
            shift 1
            ;;
        "-delete")
            deleteVerbs="\"delete\", \"deletecollection\""
            shift 1
            ;;
        "-deploy")
            extensionsResources="\"deployments\", $extensionsResources"
            shift 1
            ;;
        "-ds")
            extensionsResources="\"daemonsets\", $extensionsResources"
            shift 1
            ;;
        "-ep")
            resources="\"endpoints\", $resources"
            shift 1
            ;;
        "-ev")
            resources="\"events\", $resources"
            shift 1
            ;;
        "-file")
            file=$2
            shift 2
            ;;
        "-get")
            getVerbs="\"get\", \"watch\", \"list\""
            shift 1
            ;;
        "-ing")
            extensionsResources="\"ingresses\", $extensionsResources"
            shift 1
            ;;
        "-job")
            batchResources="\"jobs\", $batchResources"
            shift 1
            ;;
        "-limits")
            resources="\"limitranges\", $resources"
            shift 1
            ;;
        "-ns")
            ns=$2
            shift 2
            ;;
        "-netpol")
            extensionsResources="\"networkpolicies\", $extensionsResources"
            shift 1
            ;;
        "-patch")
            patchVerbs="\"patch\""
            shift 1
            ;;
        "-pdb")
            policyResources="\"poddisruptionbudgets\", $policyResources"
            shift 1
            ;;
        "-po")
            resources="\"pods\", $resources"
            shift 1
            ;;
        "-post")
            postVerbs="\"create\""
            shift 1
            ;;
        "-put")
            putVerbs="\"update\""
            shift 1
            ;;
        "-pvc")
            resources="\"persistentvolumeclaims\", $resources"
            shift 1
            ;;
        "-quota")
            resources="\"resourcequotas\", $resources"
            shift 1
            ;;
        "-rc")
            resources="\"replicationcontrollers\", $resources"
            shift 1
            ;;
        "-role")
            roleName=$2
            shift 2
        "-rs")
            extensionsResources="\"replicasets\", $extensionsResources"
            shift 1
            ;;
        "-secret")
            resources="\"secrets\", $resources"
            shift 1
            ;;
        "-sa")
            resources="\"serviceaccounts\", $resources"
            shift 1
            ;;
        "-sts")
            appsResources="\"statefulsets\", $appsResources"
            shift 1
            ;;
        "-svc")
            resources="\"services\", $resources"
            shift 1
            ;;
        "-user")
            user=$2
            shift 2
            ;;
    esac
done

function usage
{
    echo "$0 -ns NS -user USER -file FILE_NAME -role ROLE_NAME -bind BINDING_NAME RESOURCE [RESOURCE ...] VERB [VERB ...]"
    echo "File name: which yml file to save under /root/rbac_grants"
    echo "Resources:"
    echo "    -cj: cronjobs"
    echo "    -cm: configmaps"
    echo "    -deploy: deployments"
    echo "    -ds: daemonsets"
    echo "    -ep: endpoints"
    echo "    -ev: events"
    echo "    -ing: ingresses"
    echo "    -job: jobs"
    echo "    -limits: limitranges"
    echo "    -netpol: networkpolicies"
    echo "    -pdb: poddisruptionbudgets"
    echo "    -po: pods"
    echo "    -pvc: persistentvolumeclaims"
    echo "    -quota: resourcequotas"
    echo "    -rc: replicationcontrollers"
    echo "    -rs: replicasets"
    echo "    -secret: secrets"
    echo "    -sa: serviceaccounts"
    echo "    -sts: statefulsets"
    echo "    -svc: services"
    echo "Verbs:"
    echo "    -get: get, watch, list"
    echo "    -post: create"
    echo "    -put: update"
    echo "    -patch: patch"
    echo "    -delete: delete, deletecollection"
    exit 1
}

if [[ `echo $ns$user$file | grep -c "null"` -ne 0 ]]; then
    usage
fi
if [[ -z $resources && -z $extensionsResources && -z $appsResources && -z $batchResources && -z $policyResources ]]; then
    usage
fi
if [[ -z $getVerbs && -z $postVerbs && -z $putVerbs && -z $patchVerbs && -z $deleteVerbs ]]; then
    usage
fi

bak=/root/rbac_grants
if [[ ! -d $bac ]]; then
    mkdir $bac
fi

cat >> $bac/$file.yml << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $bindingName
  namespace: $ns
subjects:
- kind: User
  name: "oidc_$user"
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: $roleName
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: $ns
  name: $roleName
rules:
- apiGroups: [""]
  resources: ["xxx"]
  verbs: ["get", "watch", "list"]
EOF
kubectl apply -f $bac/
