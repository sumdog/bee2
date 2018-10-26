#!/usr/bin/env python

from os import environ, makedirs, path
from shutil import copyfile
import socket
import sys

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
    #errorfile 400 /usr/local/etc/haproxy/errors/400.http
    #errorfile 403 /usr/local/etc/haproxy/errors/403.http
    #errorfile 408 /usr/local/etc/haproxy/errors/408.http
    #errorfile 500 /usr/local/etc/haproxy/errors/500.http
    #errorfile 502 /usr/local/etc/haproxy/errors/502.http
    #errorfile 503 /usr/local/etc/haproxy/errors/503.http
    #errorfile 504 /usr/local/etc/haproxy/errors/504.http
    maxconn 4096
    mode http
    option http-server-close

frontend http
    bind :::80 v4v6
    mode  http

    # Let's Encrypt
    acl is_letsencrypt path_beg -i /.well-known/acme-challenge/

    # SSL Redirect
    redirect scheme https if !{{ ssl_fc }} !is_letsencrypt

    use_backend bk_letsencrypt if is_letsencrypt

frontend https
    # TLS/SNI
    bind :::443 v4v6 ssl crt /etc/letsencrypt/live
    mode http

    http-request redirect prefix http://%[hdr(host),regsub(^www\.,,i)] code 301 if {{ hdr_beg(host) -i www. }}

    http-request set-header X-Forwarded-For %[src]
    http-request set-header X-Forwarded-Port %[dst_port]
    http-request add-header X-Forwarded-Proto https if {{ ssl_fc }}

    {}

    {}
    default_backend bk_ssl_default

{}


backend bk_letsencrypt
    server certbot {}:8080
{}
backend bk_ssl_default
    server default_ssl 127.0.0.1:8080
"""


def awstats_config():
    if environ['AWSTATS_CONTAINER'] != 'disabled':
        return """
          # Awstats
          acl is_awstats path_beg -i /stats/
          use_backend bk_awstats if is_awstats
         """
    else:
        return ""

def awstats_backend():
    if environ['AWSTATS_CONTAINER'] != 'disabled':
        return """
            backend bk_awstats
                server awstats {}:8080
        """.format(environ['AWSTATS_CONTAINER'])
    else:
        return ""

def ssl_vhosts(domain_map):
    vhosts = ''
    for link,domains in domain_map.items():
        for domain in domains:
            if '/' in domain:
                domain = domain.split('/')[0]
            dsh = domain.replace('.', '_')
            vhosts += """
        acl {}     ssl_fc_sni -i {}
        use_backend bk_{} if {}
            """.format(dsh, domain, link, dsh)
    return vhosts

def ssl_backends(domain_map):
    backends = ''
    for link,domains in domain_map.items():
        port = 8080
        if '/' in domains[0]:
            port = domains[0].split('/')[1]
        backends += """
    backend bk_{}
      server srv_{} {}:{} init-addr libc,none check
            """.format(link, link, link, port)
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
    certbot_container = environ['CERTBOT_CONTAINER']
    domian_map = map_domains()
    config = template.format(awstats_config(),
                             ssl_vhosts(domian_map),
                             ssl_backends(domian_map),
                             certbot_container,
                             awstats_backend())

    live_crt = '/etc/letsencrypt/live'
    if not path.exists(live_crt):
        print('Creating Letsencrypt Live Directory')
        makedirs(live_crt)

    copyfile('dummy.pem', path.join(live_crt, 'dummy.pem'))
    print('Writing HAProxy Configuration')
    with open('/etc/haproxy/haproxy.cfg', 'w') as fd:
        fd.write(config)

    # reload HAProxy
    print('Reloading HAProxy')
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect('/var/run/docker.sock')
    sock.sendall(str.encode('POST /containers/{}/kill?signal=HUP HTTP/1.0\r\n\n'.format(environ['HAPROXY_CONTAINER'])))

    print('Done')
