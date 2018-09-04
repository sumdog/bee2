#!/bin/sh

if [ "$MAINTENANCE_MODE" == "true" ]; then
  echo "Maintenance Mode Enabled"
  exec nginx -c /etc/nginx/nginx-maintenance.conf
else
  echo "Standard Mode Enabled"
  exec nginx -c /etc/nginx/nginx-standard.conf
fi
