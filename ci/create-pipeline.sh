#!/bin/bash

set -e
set -x

PIPELINE=discourse
CREDENTIALS=credentials.yml

if [[ ${TARGET} == "" ]]; then
  TARGET=local
fi

# Use target-specific credentials file if available
if [[ -f credentials-${TARGET}.yml ]]; then
  CREDENTIALS=credentials-${TARGET}.yml
fi

fly validate-pipeline --config pipeline.yml

fly --target ${TARGET} set-pipeline --config pipeline.yml --pipeline ${PIPELINE} -n -l $CREDENTIALS

for resource in deploy-discourse.git discourse.git; do
  fly -t ${TARGET} check-resource --resource $PIPELINE/$resource
done

fly -t ${TARGET} unpause-pipeline -p ${PIPELINE}
