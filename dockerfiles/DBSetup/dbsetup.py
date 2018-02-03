#!/usr/bin/env python
from os import environ as env
import mysql.connector
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

# db_type: postgres or mysql
def dbs(db_type):
    return [i for i in db_list['containers'] if i['db'] == db_type]


cnx = mysql.connector.connect(user = 'root',
                              password = db_list['admin']['mysql'],
                              host = env['MYSQL_HOST'],
                              database = 'mysql')
cur = cnx.cursor()

for my in dbs('mysql'):
    (app,password) = my['container'], my['password']
    cur.execute("CREATE DATABASE IF NOT EXISTS {}".format(app))
    cur.execute("GRANT ALL ON {}.* TO '{}'@'%' IDENTIFIED BY '{}'".format(
               app,app,password))

cur.close()
cnx.close()
