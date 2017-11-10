#!/usr/bin/env python

from os import environ
from shutil import copyfile

template = """
global
    #log /dev/stdout    local0
    #log /dev/stdout    local1 notice
    #stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    ssl-default-bind-options no-sslv3 no-tls-tickets force-tlsv12
    ssl-default-bind-ciphers AES128+EECDH:AES128+EDH
    tune.ssl.default-dh-param 2048
defaults
    log     global
    option  dontlognull
    timeout connect 5000
    timeout client 50000
    timeout server 50000
    errorfile 400 /usr/local/etc/haproxy/errors/400.http
    errorfile 403 /usr/local/etc/haproxy/errors/403.http
    errorfile 408 /usr/local/etc/haproxy/errors/408.http
    errorfile 500 /usr/local/etc/haproxy/errors/500.http
    errorfile 502 /usr/local/etc/haproxy/errors/502.http
    errorfile 503 /usr/local/etc/haproxy/errors/503.http
    errorfile 504 /usr/local/etc/haproxy/errors/504.http
    maxconn 4096
    mode http
    # Add x-forwarded-for header.
    option forwardfor
    option http-server-close

frontend http
    bind :80
    mode  http

    # Let's Encrypt
    acl is_letsencrypt path_beg -i /.well-known/acme-challenge/

    # SSL Redirect
    http-request set-header X-Forwarded-Port %[dst_port]
    http-request add-header X-Forwarded-Proto https if {{ ssl_fc }}
    redirect scheme https if !{{ ssl_fc }} !is_letsencrypt

    use_backend bk_letsencrypt if is_letsencrypt

frontend https
    # TLS/SNI
    bind :443 ssl crt /etc/letsencrypt/live
    mode tcp

    tcp-request inspect-delay 5s
    tcp-request content accept if {{ req_ssl_hello_type 1 }}

    {}
    default_backend bk_ssl_default

{}


backend bk_letsencrypt
    server certbot bee2-app-certbot:8080
backend bk_ssl_default
    server default_ssl 127.0.0.1:8080
"""

def ssl_vhosts(domain_map):
    vhosts = ''
    for link,domains in domain_map.items():
        for domain in domains:
            dsh = domain.replace('.', '_')
            vhosts += """
        acl {}     ssl_fc_sni -i {}
        acl {}_www ssl_fc_sni -i www.{}
        use_backend bk_{} if {}
        use_backend bk_{} if {}_www
            """.format(dsh, domain, dsh, domain, dsh, dsh, dsh, dsh)
    return vhosts

def ssl_backends(domain_map):
    backends = ''
    for link,domains in domain_map.items():
        for domain in domains:
            dsh = domain.replace('.', '_')
            backends += """
    backend bk_{}
      server {} {}:8080 check
            """.format(dsh, dsh, link)
    return backends

def map_domains():
    domain_map = {}
    """convert bee2-app-nginx-static:dyject.com,samathia.com bee2-app-php:example.org
       to just the names"""
    for d in environ['DOMAINS'].split(' '):
        parts = d.split(':')
        domain_map[parts[0]] = parts[1].split(',')
    return domain_map

if __name__ == '__main__':
    domian_map = map_domains()
    config = template.format(ssl_vhosts(domian_map), ssl_backends(domian_map))
    copyfile('/usr/local/etc/haproxy/dummy.pem', '/etc/letsencrypt/live/dummy.pem')
    with open('/usr/local/etc/haproxy/haproxy.cfg', 'w') as fd:
        fd.write(config)
