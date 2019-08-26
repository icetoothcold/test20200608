MY_IP=`hostname -i`
PEERS=""
for i in ${ALL_IPS[@]}; do
    if [[ $i != $MY_IP ]]; then
        PEERS="        $i\n$PEERS"
    fi
done
VIP_DEVS=""
for i in ${VIPS[@]}; do
    if [[ `echo ${VIP_DEVS[@]} | grep -c $i` -eq 0 ]]; then
        VIP_DEVS="        $i dev <INTF>\n$VIP_DEVS"
    fi
done
NOTIFY=""
if [[ ! -z $NOTIFY_SCRIPT ]]; then
    NOTIFY="notify $NOTIFY_SCRIPT"
fi
sed -e "s#<NOTIFY>#$NOTIFY#" -e "s/<VIP_DEVS>/$VIP_DEVS/" -e "s/<MY_IP>/$MY_IP/" -e "s/<INTF>/$INTF/" -e "s/<AD_INT>/$AD_INT/" -e "s/<VRID>/$VRID/" -e "s/<PEERS>/$PEERS/" /config/keepalived.conf.temp > keepalived.conf
/keepalived -f keepalived.conf -P -n -l
