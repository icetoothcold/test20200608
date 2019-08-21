pw='-w ldapAdmin'
host="-H ldap://local.ldap.io:389"
#baseDN="dc=main,dc=cluster,dc=io"
#bindDN="cn=admin,dc=main,dc=cluster,dc=io"
baseDN="dc=kys,dc=io"
bindDN="cn=admin,dc=kys,dc=io"
if [[ $1 == "add" ]]; then
    if [[ $2 == "user" ]]; then
        shift 2
        sn="null"
        cn="null"
        mail="null"
        uid="null"
        userpassword="null"
        while [[ $* ]]; do
            case $1 in
                "-c")
                    cn=$2
                    uid=$2
                    shift 2
                    ;;
                "-s")
                    sn=$2
                    shift 2
                    ;;
                "-m")
                    mail=$2
                    shift 2
                    ;;
                "-p")
                    userpassword=$2
                    shift 2
                    ;;
            esac
        done
        if [[ `echo $sn$cn$mail$uid$userpassword | grep -c "null"` -ne 0 ]]; then
            echo "$0 add user -c <cn> -s <sn> -m <mail> -p <userpassword>"
        else
            ldapadd $host -D $bindDN $pw << EOF
dn: cn=$cn,ou=People,dc=main,dc=cluster,dc=io
objectClass: person
objectClass: inetOrgPerson
sn: $sn
cn: $cn
mail: $mail
uid: $uid
userpassword: $userpassword
EOF
        fi
    elif [[ $2 == "group" ]]; then
        shift 2
        cn="null"
        ns="null"
        members=""
        while [[ $* ]]; do
            case $1 in
                "-c")
                    cn=$2
                    shift 2
                    ;;
                "-n")
                    ns=$2
                    shift 2
                    ;;
                "-m")
                    members="$2 $members"
                    shift 2
                    ;;
            esac
        done
        if [[ `echo $ns$cn$members | grep -c "null"` -ne 0 ]]; then
            echo "$0 add user -c <cn> -n <ns> -m <member> -m <member> ..."
        else
            cat >> ldapcmd.add.tmp << EOF
dn: cn=$cn,ou=Groups,o=$ns,dc=main,dc=cluster,dc=io
objectClass: groupOfNames
cn: $cn
EOF
            for i in $members; do
                echo "member: cn=$i,ou=People,dc=main,dc=cluster,dc=io" >> ldapcmd.add.tmp
            done
            ldapadd $host -D $bindDN $pw -f ldapcmd.add.tmp
            rm ldapcmd.add.tmp
        fi
    else
        echo "$0 $1 {user|group} ..."
    fi
elif [[ $1 == "search" ]]; then
    if [[ $2 == "all" ]]; then
        shift 2
set -x
        ldapsearch -x $host -b $baseDN -D $bindDN $pw -LLL $*
set +x
    elif [[ $2 == "user" ]]; then
        if [[ $3 == "all" ]]; then
            shift 3
            ldapsearch -x $host -b ou=People,$baseDN -D $bindDN $pw -LLL '(objectClass=person)' $*
        elif [[ ! -z $3 ]]; then
            ldapsearch -x $host -b ou=People,$baseDN -D $bindDN $pw -LLL $3
        else
            echo "$0 $1 $2 ..."
            echo -e "\tall [attr] // attr: dn,cn,uid,..."
            echo -e "\t(pattern)  // uid=jack"
        fi
    elif [[ $2 == "ns" ]]; then
        ldapsearch -x $host -b $baseDN -D $bindDN $pw -LLL '(objectClass=organization)' $*
    elif [[ $2 == "group" ]]; then
        if [[ ! -z $3 ]]; then
            ns=$3
            if [[ `echo $4 | grep -c "="` -eq 1 ]]; then
                pattern=$4
                shift 4
                ldapsearch -x $host -b o=$ns,$baseDN -D $bindDN $pw -LLL "(&(objectClass=groupOfNames)($pattern))" $*
            else
                shift 3
                ldapsearch -x $host -b o=$ns,$baseDN -D $bindDN $pw -LLL "(objectClass=groupOfNames)" $*
            fi
        else
            echo "$0 $1 $2 <NS>..."
        fi
    else
        echo "$0 $1 ..."
        echo -e "\tall [attr] // attr: objectClass,..."
        echo -e "\tuser ..."
        echo -e "\tns"
        echo -e "\tgroup ..."
    fi
elif [[ $1 == "delete" ]]; then
    if [[ $2 == "user" ]]; then
        if [[ ! -z $3 ]]; then
            ldapdelete $host -D $bindDN $pw cn=$3,ou=People,$baseDN
        else
            echo "$0 $1 $2 <CN>"
        fi
    elif [[ $2 == "group" ]]; then
        if [[ ! -z $3 ]]; then
            if [[ ! -z $4 ]]; then
                ldapdelete $host -D $bindDN $pw cn=$4,ou=Groups,o=$3,$baseDN
            else
                echo "$0 $1 $2 $3 <CN>"
            fi
        else
            echo "$0 $1 $2 <NS> <CN>"
        fi
    else
        echo "$0 $1 {user|group} <CN>"
    fi
else
    echo $0 "{add|search|delete}"
fi
