#!/bin/sh

echo -e "POST /containers/bee2-app-haproxy/kill?signal=HUP HTTP/1.0\r\n" | \
nc -U /var/run/docker.sock
