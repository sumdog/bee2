#!/bin/sh

cd /volumes
for v in /volumes/*; do
  cd "$v"
  rm * -rf
done
cd /
tar xvf restore.tar
