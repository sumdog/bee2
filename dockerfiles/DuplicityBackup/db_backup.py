#!/usr/bin/env python
from os import environ as env, unlink, system
import sys
from os.path import join, basename
import json
from datetime import datetime
import subprocess

# Format:
# { "admin":
#     {"mysql": "***", "postgres": "***", "redis": "***"},
#   "containers":
#     [
#       {"container": "somename", "db": "postgres", "password": "****"},
#       {"container": "somename", "db": "mysql", "password": "****"}
#     ]
# }
db_list = json.loads(env['DATABASE_JSON'])

def normalize(name):
    normalized = name.replace('-', '_')
    if name != normalized:
        print('{} normalized to {}'.format(name, normalized))
    return normalized

def run(cmd):
    p = subprocess.Popen(cmd, shell=True, stdout=sys.stdout, stderr=sys.stderr)
    p.wait()

# db_type: postgres or mysql
def dbs(db_type):
    return [i for i in db_list['containers'] if i['db'] == db_type]

# Multiple containers that share the same database
# Taken from http://stackoverflow.com/questions/9427163/ddg#9427216
def without_dups(db_type):
    return [dict(t) for t in {tuple(d.items()) for d in dbs(db_type)}]

def timestamp_sql_file(db, db_type):
    sqlfile = '{}-{}.{}.sql'.format(db, datetime.utcnow().strftime('%Y-%m-%d-%H:%m:%S'), db_type)
    path = env['BACKUP_SQL_DIR']
    return join(path, sqlfile)

def b2_upload(sqlfile):
    cmd = 'b2 upload-file {} {} {}'.format(env['BB_SQL_BUCKET'], sqlfile, basename(sqlfile))
    run(cmd)
    unlink(sqlfile)

# Mysql

if not 'mysql' in db_list['admin']:
    print('No containers configured for mysql')
else:
    for my in without_dups('mysql'):
        (app,password) = normalize(my['container']), my['password']
        mysql_dump_file = timestamp_sql_file(app, 'my')
        print('Dumping {} to {}'.format(app, mysql_dump_file))
        cmd = 'mysqldump -h {} -P 3306 -u root --password={} --result-file={} {}'.format(
              env['MYSQL_HOST'], db_list['admin']['mysql'], mysql_dump_file, app)
        run(cmd)
        b2_upload(mysql_dump_file)

# Postgres

if not 'postgres' in db_list['admin']:
    print('No containers configured for postgres')
else:
    for pg in without_dups('postgres'):
        (app,password) = normalize(pg['container']), pg['password']
        pg_dump_file = timestamp_sql_file(app, 'pg')

        print('Dumping {} to {}'.format(app, pg_dump_file))
        cmd = 'env PGPASSWORD="{}" pg_dump -Fc -d {} -h {} -f {} -U postgres'.format(
          db_list['admin']['postgres'], app, env['POSTGRES_HOST'], pg_dump_file
        )
        run(cmd)
        b2_upload(pg_dump_file)
