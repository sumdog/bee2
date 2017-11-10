#!/usr/bin/env python3

from os import path, environ
from time import sleep
from subprocess import call
from sys import stderr

CERT_BASE = '/etc/letsencrypt/live'

def create_pem(domain):
    combined = path.join(CERT_BASE, '{}-combined.pem'.format(domain))
    with open(combined, 'w') as f:
        files = [path.join(CERT_BASE, domain, 'fullchain.pem'),
                 path.join(CERT_BASE, domain, 'privkey.pem')]
        for file in files:
            with open(file) as infile:
                f.write(infile.read())
            print('Created {}'.format(combined))

def convert_domains():
    domains = []
    """convert bee2-app-nginx-static:example.com,example.net bee2-app-php:example.org
       to just the names"""
    for d in environ['DOMAINS'].split(' '):
        domains = domains + (d.split(':')[1].split(','))
    return domains

if __name__ == '__main__':

    domains = convert_domains()
    email = environ['EMAIL']
    dryrun = environ['TEST'].lower() == 'true'
    port = environ['PORT']
    renew = int(environ['RENEW_INTERVAL'])

    while call(['check_docker', '--containers', 'bee2-app-haproxy', '--status', 'running']) != 0:
        print('Waiting on HAProxy to become active')
        sleep(2)

    while True:
        for domain in domains:
            print('Processing {}'.format(domain))
            cmd = ['/usr/local/bin/certbot', 'certonly', '--standalone',
                   '--preferred-challenges', 'http',
                   '--http-01-port', port, '--agree-tos', '--renew-by-default',
                   '--non-interactive', '--email', email, '-d', domain, '-d',
                   'www.{}'.format(domain)]
            if dryrun:
                cmd.append('--test-cert')
            if call(cmd) == 0:
                create_pem(domain)
                print('Sending reload to HAProxy Docker Container')
                call(['/opt/reload-haproxy.sh'])
            else:
                stderr.write('Error running certbot. Skipping {}\n'.format(domain))

        print('Sleeping {} minutes...'.format(renew))
        sleep(renew * 60)
