#!/bin/bash
# this file should be executable, e.g. chmod +x
state=$3
# change this to slb IP
slb="a.b.c.d"
# 389 for ldap, 8080 for harbor
port=389
if [[ $state == "MASTER" ]]; then
	drop_rule_idx=`iptables -nvL DOCKER-USER --line-numbers | grep "${slb}.*dpt:${port}" | awk '/DROP/{print $1}'`
	if [[ ! -z $drop_rule_idx ]]; then
		iptables -D DOCKER-USER $drop_rule_idx
	fi
else
	# BACKUP or FAULT(check failed)
	drop_rule_idx=`iptables -nvL DOCKER-USER --line-numbers | grep "${slb}.*dpt:${port}" | awk '/DROP/{print $1}'`
	if [[ -z $drop_rule_idx ]]; then
		iptables -I DOCKER-USER 1 -s $slb -p tcp --dport $port -j DROP
	fi
fi
