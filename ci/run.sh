#!/bin/bash

set -e

# todo check into bosh-deployment
pushd bosh-deployment
	cat >>misc/ipv6/bosh.yml <<LOL

- type: replace
  path: /instance_groups/name=bosh/properties/director/address
  value: "[((internal_ip))]"

# eventmachine does not like ipv6 addresses
- type: replace
  path: /instance_groups/name=bosh/properties/nats/address
  value: "localhost"

- type: replace
  path: /variables/name=nats_server_tls/options/alternative_names/-
  value: localhost
LOL
popd

if [[ $HYBRID ]]; then
	./bosh-ipv6-acceptance-tests/ci/test-hybrid-director.sh
else
	./bosh-ipv6-acceptance-tests/ci/test-pure-director.sh
fi
