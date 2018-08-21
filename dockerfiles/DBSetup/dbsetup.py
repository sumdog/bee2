#!/usr/bin/env python
from os import environ as env
import mysql.connector
import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
import json

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

# db_type: postgres or mysql
def dbs(db_type):
    return [i for i in db_list['containers'] if i['db'] == db_type]

# Mysql

if not 'mysql' in db_list['admin']:
    print('No containers configured for mysql')
else:
    cnx = mysql.connector.connect(user = 'root',
                                  password = db_list['admin']['mysql'],
                                  host = env['MYSQL_HOST'],
                                  database = 'mysql')
    cur = cnx.cursor()

    for my in dbs('mysql'):
        (app,password) = normalize(my['container']), my['password']
        print('MySQL DB Setup: {}'.format(app))
        cur.execute("CREATE DATABASE IF NOT EXISTS {}".format(app))
        cur.execute("GRANT ALL ON {}.* TO '{}'@'%' IDENTIFIED BY '{}'".format(
                   app,app,password))

    cur.close()
    cnx.close()

# Postgres

if not 'postgres' in db_list['admin']:
    print('No containers configured for postgres')
else:
    conn = psycopg2.connect(dbname = 'postgres', user = 'postgres',
                            password = db_list['admin']['postgres'],
                            host = env['POSTGRES_HOST'])
    conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
    cur = conn.cursor()

    for pg in dbs('postgres'):
        (app,password) = normalize(pg['container']), pg['password']
        sql = "SELECT COUNT(*) = 0 FROM pg_catalog.pg_database WHERE datname = '{}'"
        cur.execute(sql.format(app))
        not_exists_row = cur.fetchone()
        not_exists = not_exists_row[0]
        if not_exists:
            print('Postgres DB Setup: {}'.format(app))
            cur.execute('CREATE DATABASE {}'.format(app))
            sql = "CREATE ROLE {} LOGIN PASSWORD '{}'".format(app, password)
            cur.execute(sql)
            sql = 'GRANT ALL ON DATABASE {} to {}'.format(app, app)
            cur.execute(sql)
        else:
            print('Postgres DB {} Exists'.format(app))
