#!/bin/bash
# this file should be executable, e.g. chmod +x
state=$3
# change this to slb IP
slb="a.b.c.d"
# 389 for ldap, 8080 for harbor
port=389
if [[ $state == "MASTER" ]]; then
	drop_rule_idx=""
	for i in {1..6}; do
		drop_rule_idx=`iptables -nvL DOCKER-USER --line-numbers | grep "${slb}.*dpt:${port}" | awk '/DROP/{print $1}'`
		if [[ $? -eq 0 ]]; then
			break
		fi
		sleep 1
	done
	if [[ ! -z $drop_rule_idx ]]; then
		for i in {1..6}; do
			iptables -D DOCKER-USER $drop_rule_idx
			if [[ $? -eq 0 ]]; then
				break
			fi
			sleep 1
		done
	fi
else
	# BACKUP or FAULT(check failed)
	drop_rule_idx=""
	for i in {1..6}; do
		drop_rule_idx=`iptables -nvL DOCKER-USER --line-numbers | grep "${slb}.*dpt:${port}" | awk '/DROP/{print $1}'`
		if [[ $? -eq 0 ]]; then
			break
		fi
		sleep 1
	done
	if [[ -z $drop_rule_idx ]]; then
		for i in {1..6}; do
			iptables -I DOCKER-USER 1 -s $slb -p tcp --dport $port -j DROP
			if [[ $? -eq 0 ]]; then
				break
			fi
			sleep 1
		done
	fi
fi
