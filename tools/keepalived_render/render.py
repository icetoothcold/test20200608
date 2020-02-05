#!/usr/bin/python3

import jinja2
import netaddr
import os
import sys
import yaml


j2_tml = """vrrp_instance {{ name }} {
    state BACKUP
    interface {{ interface }}
    garp_master_delay 2
    virtual_router_id {{ vrid }}
    priority 100
    nopreempt
    advert_int 1
    virtual_ipaddress {
        {{ vip }} dev {{ interface }}
    }
    unicast_src_ip {{ node_ip }}
    unicast_peer {
        {{ peer_ip }}
    }
}
"""


def exit(msg):
    print(msg)
    sys.exit(1)


def validate_ip(ip):
    try:
        netaddr.IPAddress(ip)
    except Exception:
        exit("%s is not a valid IP" % ip)


def get_data(fileName):
    if not os.path.exists(fileName):
        exit("File %s not exits" % fileName)
    data = {}
    try:
        with open(fileName) as f:
            data = yaml.load(f)
    except Exception:
        exit("Failed to parse file %s" % fileName)
    for k in ('interfaceName', 'nodeIPs', 'components'):
        if k not in data:
            exit("Key %s not found in file %s" % (k, fileName))
    if len(data['nodeIPs']) != 2:
        exit("Only 2 nodeIPs are needed")
    for ip in data['nodeIPs']:
        validate_ip(ip)
    for comp in data['components']:
        for k in ('name', 'vrid', 'vip'):
            if k not in comp:
                exit("Missing key %s" % k)
        validate_ip(comp['vip'])
        if not(1 < comp['vrid'] < 255):
            exit("%s is not a valid vird" % comp['vrid'])
    return data


def gen(data):
    interface = data['interfaceName']
    template = jinja2.Template(j2_tml)
    for idx in (0, 1):
        ip = data['nodeIPs'][idx]
        peer = data['nodeIPs'][1-idx]
        path = './%s' % ip
        if os.path.exists(path):
            if not os.path.isdir(path):
                os.remove(path)
        else:
            os.mkdir(path)
        for comp in data['components']:
            name = comp['name']
            try:
                with open('%s/%s.conf' % (path, name), 'w+') as f:
                    f.write(template.render(
                        interface=interface, vrid=comp['vrid'],
                        name=name, vip=comp['vip'],
                        node_ip=ip, peer_ip=peer))
            except Exception as e:
                exit("Failed to render keepalived config file for %s" % name)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        exit("usage: python3 %s <VIP_INFO_YAML>" % __file__)
    data_file = sys.argv[1]
    data = get_data(data_file)
    gen(data)
