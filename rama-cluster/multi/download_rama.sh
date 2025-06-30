#!/usr/bin/env bash

cd /data/rama

until curl -sSL '${rama_source_path}' --output rama.zip
do
  echo "Failed to download rama.zip from ${rama_source_path}. Retrying" \
       >> download.log
  sleep 5
done

unzip rama.zip
rm download.log