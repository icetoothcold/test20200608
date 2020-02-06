#!/usr/bin/python3

import jinja2
import netaddr
import os
import sys
import yaml


j2_tml = """global
    log         127.0.0.1 local2 info
    maxconn     4000
    user        root
    group       root
    daemon

defaults
    mode                        tcp
    log                         global
    option                      redispatch
    option http-server-close
    retries                     3
    timeout http-request        10s
    timeout queue               1m
    timeout connect             10s
    timeout client              1m
    timeout server              1m
    timeout http-keep-alive     10s
    timeout check               10s
    maxconn                     3000

{% for frontend in data.httpFrontends %}
frontend {{ frontend.name }}
    mode http
    bind :{{ frontend.port }}
    {%- for svc in frontend.services %}
    acl is_{{ svc.name }} hdr_beg(host) -i {{ svc.domain }}
    {%- endfor %}
    {%- for svc in frontend.services %}
        {%- if svc.deny %}
    http-request deny if is_{{ svc.name }}
        {%- endif %}
        {%- if svc.allowOnly %}
    http-request deny if !is_{{ svc.name }}
        {%- endif %}
    {%- endfor %}
    {%- for svc in frontend.services %}
        {%- if svc.backend %}
    use_backend {{ svc.backend }} if is_{{ svc.name }}
        {%- endif %}
    {%- endfor %}
    default_backend {{ frontend.defaultBackend }}
{% endfor %}
{% for backend in data.httpBackends %}
backend {{ backend.name }}
    mode http
    balance roundrobin
    cookie  JSESSIONID prefix
    stats   hide-version
    option  httpclose
    {%- for server in backend.servers %}
    server {{ server.ip.replace('.', '_') }} {{ server.ip }}:{{ server.port }}
    {%- endfor %}
{% endfor %}
{% for svc in data.tcpServices %}
frontend {{ svc.name }}
    mode tcp
    bind :{{ svc.port }}
    default_backend {{ svc.name }}_be

backend {{ svc.name }}_be
    mode tcp
    balance roundrobin
    {%- for server in svc.servers %}
    server {{ server.ip.replace('.', '_') }} {{ server.ip }}:{{ server.port }}
    {%- endfor %}
{% endfor %}
"""


def exit(msg):
    print(msg)
    sys.exit(1)


def validate_ip(ip):
    try:
        netaddr.IPAddress(ip)
    except Exception:
        exit("%s is not a valid IP" % ip)


def validate_port(port):
    if not(isinstance(port, int) and (port in (80, 443) or port > 1024)):
        exit("%s is not a valid port" % port)


def validate_keys(data, keys):
    for k in keys:
        if k not in data:
            exit("Key %s is missing" % k)


def get_data(fileName):
    if not os.path.exists(fileName):
        exit("File %s not exits" % fileName)
    data = {}
    try:
        with open(fileName) as f:
            data = yaml.load(f)
    except Exception:
        exit("Failed to parse file %s" % fileName)
    if 'name' not in data:
        exit("Key name not found in file %s" % fileName)
    if 'httpFrontends' not in data:
        exit("Key httpFrontends not found in file %s" % fileName)
    for fe in data['httpFrontends']:
        validate_keys(fe, ('name', 'port', 'defaultBackend', 'services'))
        validate_port(fe['port'])
        for svc in fe['services']:
            validate_keys(svc, ('name', 'domain'))
    if 'httpBackends' not in data:
        exit("Key httpBackends not found in file %s" % fileName)
    for be in data['httpBackends']:
        validate_keys(be, ('name', 'servers'))
        for svr in be['servers']:
            validate_ip(svr['ip'])
            validate_port(svr['port'])
    if 'tcpServices' not in data:
        exit("Key tcpServices not found in file %s" % fileName)
    for svc in data['tcpServices']:
        validate_keys(svc, ('name', 'port', 'servers'))
        for svr in svc['servers']:
            validate_ip(svr['ip'])
            validate_port(svr['port'])
    return data


def gen(data):
    template = jinja2.Template(j2_tml)
    try:
        with open('./%s' % data['name'], 'w+') as f:
            f.write(template.render(data=data))
    except Exception as e:
        exit("Failed to render haproxy config file for %s" % data['name'])


if __name__ == '__main__':
    if len(sys.argv) != 2:
        exit("usage: python3 %s <VIP_INFO_YAML>" % __file__)
    data_file = sys.argv[1]
    data = get_data(data_file)
    gen(data)
