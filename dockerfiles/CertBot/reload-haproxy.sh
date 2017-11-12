#!/bin/sh

echo -e "POST /containers/$HAPROXY_CONTAINER/kill?signal=HUP HTTP/1.0\r\n" | \
nc -U /var/run/docker.sock
