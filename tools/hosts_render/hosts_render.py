#!/usr/bin/python3
#
# refer: https://stackoverflow.com/questions/37200150/can-i-dump-blank-instead-of-null-in-yaml-pyyaml

import ipaddress
import netaddr
import sys
import yaml

from yaml.representer import Representer
from yaml.dumper import Dumper
from yaml.emitter import Emitter
from yaml.serializer import Serializer
from yaml.resolver import Resolver


class MyRepresenter(Representer):
    def represent_none(self, data):
        return self.represent_scalar(u'tag:yaml.org,2002:null', u'')


class MyDumper(Emitter, Serializer, MyRepresenter, Resolver):
    def __init__(self, stream, default_style=None, default_flow_style=None,
                 canonical=None, indent=None, width=None, allow_unicode=None,
                 line_break=None, encoding=None, explicit_start=None,
                 explicit_end=None, version=None, tags=None):
        Emitter.__init__(self, stream, canonical=canonical,
                         indent=indent, width=width,
                         allow_unicode=allow_unicode, line_break=line_break)
        Serializer.__init__(self, encoding=encoding,
                            explicit_start=explicit_start,
                            explicit_end=explicit_end,
                            version=version, tags=tags)
        MyRepresenter.__init__(self, default_style=default_style,
                               default_flow_style=default_flow_style)
        Resolver.__init__(self)

MyRepresenter.add_representer(type(None), MyRepresenter.represent_none)


def parse_data(data_file):
    data = yaml.safe_load(open(data_file))
    hosts = {}
    master_hosts = {}
    node_hosts = {}
    etcd_hosts = {}
    passwords = {}
    password = data['password']
    for block in data['hosts']:
        hostname_prefix = block['hostnamePrefix']
        hostname_index = int(block['indexFrom'])
        index_len = int(block['indexLen'])
        role = block['role']
        first_ip = block['ipstart']
        end_ip = block['ipend']
        ip_idx = netaddr.IPAddress(first_ip).value
        while True:
            ip = str(ipaddress.ip_address(ip_idx))
            hostname = '%s%s' % (
                hostname_prefix, str(hostname_index).zfill(index_len))
            hosts[hostname] = {
                'ansible_host': ip,
                'ip': ip,
                'access_ip': ip
                }
            if role == 'master':
                master_hosts[hostname] = None
                etcd_hosts[hostname] = None
            elif role == 'node':
                node_hosts[hostname] = None
            passwords[ip] = password
            if ip == end_ip:
                break
            ip_idx+=1
            hostname_index+=1
    return hosts, master_hosts, node_hosts, etcd_hosts, passwords


def render_inventory_hosts(hosts, master_hosts, node_hosts, etcd_hosts):
    return {
        'all': {
            'hosts': hosts,
            'children': {
                'kube-master': {'hosts': master_hosts},
                'kube-node': {'hosts': node_hosts},
                'etcd': {'hosts': etcd_hosts},
                'k8s-cluster': {'children': {
                    'kube-master': None, 'kube-node': None}},
                'calico-rr': {'hosts': {}}
                }
            }
        }


def save_inventory_hosts(data):
    with open('./rendered_hosts.yml', 'w+') as f:
        yaml.dump(data, stream=f, Dumper=MyDumper, default_flow_style=False)


def save_cluster_hosts(data):
    with open('./rendered_cluster.yml', 'w+') as f:
        yaml.dump(data, stream=f, Dumper=MyDumper, default_flow_style=False)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("usage: python3 %s <NODE_INFO_YAML>" % __file__)
        sys.exit(1)
    data_file = sys.argv[1]
    hosts, master_hosts, node_hosts, etcd_hosts, passwords = parse_data(
        data_file)
    save_inventory_hosts(render_inventory_hosts(
        hosts, master_hosts, node_hosts, etcd_hosts))
    save_cluster_hosts(passwords)
