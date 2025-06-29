#!/usr/bin/env bash

# Upload the rama.zip file to the /data/rama directory on the conductor
key_opts=""
if [ -n "${4:-}" ]; then
  key_opts="-i $4"
fi
scp -o "StrictHostKeyChecking no" $key_opts "$1" "$2@$3:/home/$2/rama.zip"
