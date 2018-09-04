#!/usr/bin/env python3

from os import environ, execv
import subprocess

if __name__ == '__main__':

    tasks = {}

    for k,v in environ.items():
        if k.startswith('RUN_'):
            task_name = k.split('_')[1]
            if not task_name in tasks:
                tasks[task_name] = {}
            tasks[task_name]['container'] = v
        elif k.startswith('WHEN_'):
            task_name = k.split('_')[1]
            if not task_name in tasks:
                tasks[task_name] = {}
            tasks[task_name]['schedule'] = v

    with open('/etc/crontabs/root', 'w') as ctab:
        for name, cmds in tasks.items():
            ctab.write('{}\tdocker start {}\n'.format(cmds['schedule'], cmds['container']))

    subprocess.call(['crond', '-f'])
