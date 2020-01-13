#!/bin/bash
set -o nounset
# ########################################################################
# Globals, settings
# ########################################################################
#BOND_MODE="mode=balance-xor miimon=100 xmit_hash_policy=layer3+4"
BOND_MODE="mode=1 miimon=100 fail_over_mac=active"
UDEV_FILE="/etc/udev/rules.d/60-persistent-net.rules"
BOND_PREFIX="cbond"
VF_PREFIX="VF"

# PF list example: eth0,eth1
PF_LIST=$1
VF_NUM=0
# split PF_LIST to PF_ARR. separator is ','
IFS=',' read -r -a PF_ARR <<< "${PF_LIST}"

installed () {
    command -v "$1" >/dev/null 2>&1
}

# Google Styleguide says error messages should go to standard error.
warn () {
    echo "$@" >&2
}
die () {
    status="$1"
    shift
    warn "$@"
    exit "$status"
}

disable_networkmanager () {
    # disable NetworkManager
    systemctl disable NetworkManager
    systemctl stop NetworkManager
}

get_sriov_totalvfs_minimum () {
    # get pf sriov_totalvfs minimum value
    local max
    for PF in "${PF_ARR[@]}"; do
        ip link set "${PF}" up

        max=$( cat "/sys/class/net/${PF}/device/sriov_totalvfs" ) || {
            die 4 "get ${PF} sriov_totalvfs  failed"
        }
        if [[ ${VF_NUM} -eq 0 ]]; then
            VF_NUM=${max}
        elif [[ ${max} -lt ${VF_NUM} ]]; then
            VF_NUM=${max}
        fi
    done
}

set_sriov () {
    for PF in "${PF_ARR[@]}"; do
        # reset sriov number
        echo 0 > "/sys/class/net/${PF}/device/sriov_numvfs"
        sleep 3
        # setting sriov_numvfs
        echo "${VF_NUM}" > "/sys/class/net/${PF}/device/sriov_numvfs"
        sleep 3

        if cat "/sys/class/net/${PF}/device/virtfn0/enable"; then
            echo "${PF} sriov enable"
        else
            die 3 "${PF} sriov enable failed"
        fi
    done
}

update_rclocal () {
    # backup /etc/rc.d/rc.local
    if [[ -e /etc/rc.d/rc.local ]]; then
        cp /etc/rc.d/rc.local "/root/rc.local.bak$(date +%s)"
    fi

    # init /etc/rc.d/rc.local
    cat << EOF > /etc/rc.d/rc.local
#!/bin/bash
touch /var/lock/subsys/local
EOF

    chmod +x /etc/rc.d/rc.local

    local pf_num=0
    for PF in "${PF_ARR[@]}"; do
        # set rc.local
        cat << EOF >> /etc/rc.d/rc.local
echo ${VF_NUM} > /sys/class/net/${PF}/device/sriov_numvfs
sleep 5
EOF

        # set VF if config
        for ((vf_num=0; vf_num<"${VF_NUM}"; vf_num++)); do
            local vf_name="${VF_PREFIX}${pf_num}${vf_num}"

            # set rc.local
            cat << EOF >> /etc/rc.d/rc.local
ip link set ${vf_name} up
EOF
        done

        (( pf_num++ ))
    done

    for ((vf_num=0; vf_num<"${VF_NUM}"; vf_num++)); do
        local vf_bond_name="${BOND_PREFIX}${vf_num}"
        # set rc.local
        cat << EOF >> /etc/rc.d/rc.local
ifup ${vf_bond_name}
EOF
    done
}

update_udev_file () {
    # check udevadm exist
    if ! installed udevadm; then
        die 2 "udevadm not installed"
    fi

    # init udev file
    if [[ ! -e ${UDEV_FILE} ]]; then
        touch ${UDEV_FILE}
    else
        echo -n '' > ${UDEV_FILE}
    fi

    local pf_num=0
    for PF in "${PF_ARR[@]}"; do

        for dev_path in /sys/class/net/"${PF}"/device/virtfn*; do
            [[ -d ${dev_path} ]] || break
            # vf_num start number is 0
            local vf_num
            vf_num=$(awk -F'virtfn' '{print $(NF)}' <<< "${dev_path}")
            local vf_name="${VF_PREFIX}${pf_num}${vf_num}"
            local vf_pci_addr
            vf_pci_addr=$(awk -F= '/PCI_SLOT_NAME/{print $(NF) }' < "${dev_path}"/uevent)

            # set udev file
            cat << EOF >> ${UDEV_FILE}
ACTION=="add", SUBSYSTEM=="net", KERNELS=="${vf_pci_addr}", NAME:="${vf_name}"
EOF
        done

        (( pf_num++ ))
    done
}

gen_nic_config () {
    local pf_num=0
    for PF in "${PF_ARR[@]}"; do

        for ((vf_num=0; vf_num<"${VF_NUM}"; vf_num++)); do
            local vf_name="${VF_PREFIX}${pf_num}${vf_num}"
            local vf_bond_name="${BOND_PREFIX}${vf_num}"

            # create VF ifcfig file
            cat << EOF > "/etc/sysconfig/network-scripts/ifcfg-${vf_name}"
DEVICE=${vf_name}
TYPE=Ethernet
USERCTL=no
SLAVE=yes
MASTER=${vf_bond_name}
BOOTPROTO=none
ONBOOT=yes
EOF
        done

        (( pf_num++ ))
    done

    for ((vf_num=0; vf_num<"${VF_NUM}"; vf_num++)); do
        local vf_bond_name="${BOND_PREFIX}${vf_num}"
        # create VF bond ifcfig file
        cat << EOF > "/etc/sysconfig/network-scripts/ifcfg-${vf_bond_name}"
DEVICE=${vf_bond_name}
ONBOOT=yes
USERCTL=no
TYPE=Ethernet
BOOTPROTO=none
BONDING_OPTS="${BOND_MODE}"
NM_CONTROLLED=no
EOF
    done
}

# ##############################################################################
# The main() function is called at the end of the script.
# only main function can use function( die ) and exit
# ##############################################################################
main () {
    disable_networkmanager
    get_sriov_totalvfs_minimum
    set_sriov
    update_rclocal
    update_udev_file
    gen_nic_config

    echo "setting success. Please reboot for effective device"
}

main
