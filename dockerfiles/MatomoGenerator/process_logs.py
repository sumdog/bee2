#!/usr/bin/env python3
import os
import time
import logging
import subprocess
import socket


log = logging.getLogger('matomogen')
log.setLevel(logging.DEBUG)
console = logging.StreamHandler()
console.setFormatter(logging.Formatter('%(asctime)s: %(message)s'))
log.addHandler(console)


def reload_web_container(container):
    """Sends the HUP signal to a container"""
    log.info(f'Reloading Container {container}')
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect('/var/run/docker.sock')
    sock.sendall(str.encode('POST /containers/{}/kill?signal=HUP HTTP/1.0\r\n\n'.format(container)))
    log.info(f'HUP Signal to {container} sent')


if __name__ == '__main__':

    nginx_container = os.environ['NGINX_CONTAINER']
    log_path = os.environ['LOG_PATH']
    rotate_path = os.environ['ROTATE_PATH']
    log_config = os.environ['LOG_CONFIG']
    matomo_token = os.environ['MATOMO_TOKEN']
    matomo_url = os.environ['MATOMO_URL']
    process_time = time.strftime('%Y-%m-%d-%H:%M:%S')

    log.info(f'NGINX Container: {nginx_container}')
    log.info(f'Log Path {log_path}')
    log.info(f'Processed Path {rotate_path}')
    log.info(f'Log Config {log_config}')
    log.info(f'Timestamp {process_time}')

    sites = []
    for l in log_config.split(','):
        parts = l.split(':')
        sites.append({'id': parts[0], 'host': parts[1]})

    for site in sites:
        log_file = os.path.join(log_path, f"{site['host']}.log")
        if not os.path.isfile(log_file):
            log.error(f"Could not find log {log_file}. Skipping...")
        else:
            process_logfile = os.path.join(rotate_path, f"{site['host']}.{process_time}.log")
            log.info(f'Moving {log_file} to {process_logfile}')
            os.rename(log_file, process_logfile)
            reload_web_container(nginx_container)

            cmd = ['import_logs.py', f'--token-auth={matomo_token}',
                   f'--url={matomo_url}',
                   f"--idsite={site['id']}",
                   '--enable-bots',
                   '--enable-http-errors',
                   '--enable-http-redirects',
                   ' --enable-reverse-dns',
                   '--exclude-path=*.json',
                   #'--dry-run'
                   process_logfile]

            log.info(f"Importing logs for {site['host']}")
            log.debug(f'Command :: {cmd}')
            result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            log.debug(result.stdout)

            if result.returncode != 0:
                log.error("Error Processing Logs")
                log.error(result.stderr)
            else:
                log.info(f"Log Import for {site['host']} complete")

                log.info("Marking log as processed")
                processed_name = f'{process_logfile}.processed'
                os.rename(process_logfile, processed_name)

                log.info("Compressing Log")
                cmd = ['xz', processed_name]
                result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                if result.returncode != 0:
                    log.error("Error Compressing Processed Logs")
                    log.error(result.stderr)
                else:
                    log.info("Process Logs Compressed")
                    log.debug(result.stdout)
