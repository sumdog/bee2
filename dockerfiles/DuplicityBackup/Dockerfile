FROM ubuntu

ENV BB_VOL_BUCKET volume-backups
ENV BB_SQL_BUCKET sql-backups
ENV BB_APP_ID insert_bb_app_id
ENV BB_APP_KEY insert_bb_app_key

ENV VOLUME_ENABLED enabled
ENV DATABASE_ENABLED enabled

ENV BACKUP_VOL_DIR /backup
ENV BACKUP_SQL_DIR /sql
ENV DATABASE_JSON "{}"

RUN apt-get update && \
    apt-get install -y software-properties-common && \
    add-apt-repository -y ppa:duplicity-team/ppa && \
    apt-get update && \
    apt-get install -y duplicity python-pip mysql-client postgresql-client && \
    pip install b2

COPY backup.sh /
COPY db_backup.py /
RUN chmod 700 /backup.sh /db_backup.py

CMD [ "/backup.sh" ]
