MY_IP=`hostname -i`
PEERS=""
for i in ${ALL_IPS[@]}; do
    if [[ $i != $MY_IP ]]; then
        PEERS="        $i\n$PEERS"
    fi
done
sed -e "s/<MY_IP>/$MY_IP/" -e "s/<VIP>/$VIP/" -e "s/<INTF>/$INTF/" -e "s/<AD_INT>/$AD_INT/" -e "s/<VRID>/$VRID/" -e "s/<PEERS>/$PEERS/" /config/keepalived.conf.temp > keepalived.conf
/keepalived -f keepalived.conf -P -n -l
