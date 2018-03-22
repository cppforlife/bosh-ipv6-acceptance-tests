#!/bin/bash

set -eu

time fly -t ipv6-test execute -p -i bosh-ipv6-acceptance-tests=.. -i bosh-deployment=/Users/pivotal/workspace/bosh-deployment6 -c run.yml
