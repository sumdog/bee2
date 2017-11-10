FROM ubuntu

RUN mkdir -p /volumes
COPY restore-volumes.sh /
RUN chmod 700 restore-volumes.sh

COPY restore.tar /

ENTRYPOINT /restore-volumes.sh
