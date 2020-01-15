for ns in `kubectl get ns | awk '{if(NR>1)print $1}'`; do
	kubectl -n $ns get netpol default-ingress-deny-all
	if [[ $? -ne 0 ]]; then
		continue
	fi
	# master1 tunl0 IP
	kubectl -n $ns patch netpol default-ingress-deny-all --type='json' -p='[{"op":"add", "path":"/spec/ingress/0/from/0", "value":{"ipBlock":{"cidr":"MASTER1_TUNL0_IP/32"}}}]'
	# master2 tunl0 IP
	kubectl -n $ns patch netpol default-ingress-deny-all --type='json' -p='[{"op":"add", "path":"/spec/ingress/0/from/0", "value":{"ipBlock":{"cidr":"MASTER2_TUNL0_IP/32"}}}]'
	# master3 tunl0 IP
	kubectl -n $ns patch netpol default-ingress-deny-all --type='json' -p='[{"op":"add", "path":"/spec/ingress/0/from/0", "value":{"ipBlock":{"cidr":"MASTER3_TUNL0_IP/32"}}}]'
done
