#!/bin/bash

set -e -x

echo "This test ensures that Director can be deployed in hybrid IPv4+IPv6 configuration"

apt-get -y update
apt-get -y install wget

echo "-----> `date`: Starting docker"
source bosh-ipv6-acceptance-tests/ci/docker-lib.sh

export OUTER_CONTAINER_IP=$(ruby -rsocket -e 'puts Socket.ip_address_list
                        .reject { |addr| !addr.ip? || addr.ipv4_loopback? || addr.ipv6? }
                        .map { |addr| addr.ip_address }')

export DOCKER_HOST="tcp://${OUTER_CONTAINER_IP}:4243"

docker_certs_dir=$(mktemp -d)
start_docker ${docker_certs_dir}

echo "-----> `date`: Deploying IPv4 Director"
bosh create-env bosh-deployment/bosh.yml \
  -o bosh-deployment/docker/cpi.yml \
  -o bosh-deployment/jumpbox-user.yml \
  -o bosh-deployment/uaa.yml \
  -o bosh-deployment/credhub.yml \
  -v director_name=ipv4-plus-ipv6 \
  -v internal_cidr=10.245.0.0/16 \
  -v internal_gw=10.245.0.1 \
  -v internal_ip=10.245.0.3 \
  --state state.json \
  --vars-store creds.yml \
  -v director_name=docker \
  -v docker_host=$DOCKER_HOST \
  --var-file docker_tls.ca=${docker_certs_dir}/ca.pem \
  --var-file docker_tls.certificate=${docker_certs_dir}/cert.pem \
  --var-file docker_tls.private_key=${docker_certs_dir}/key.pem \
  -o bosh-ipv6-acceptance-tests/ci/local-bosh-release.yml \
  -o bosh-ipv6-acceptance-tests/ci/local-docker-cpi.yml \
  -v network=ipv4-only

export BOSH_ENVIRONMENT="https://10.245.0.3:25555"
export BOSH_CA_CERT="$(bosh int creds.yml --path /director_ssl/ca)"
export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET="$(bosh int creds.yml --path /admin_password)"

echo "-----> `date`: Update cloud config"
bosh -n update-cloud-config bosh-ipv6-acceptance-tests/ci/cloud-config.yml \
	-v internal_cidr=fd8d:a46c:6ec2:6709:0000:0000:0000:0000/64 \
  -v internal_gw=fd8d:a46c:6ec2:6709:0000:0000:0000:0001 \
  -v internal_ip=fd8d:a46c:6ec2:6709:0000:0000:0000:0006 \
  -v internal_dns="['2001:4860:4860::8888']" \
  -v docker_network_name=ipv6-only

bosh -n update-config --type cloud --name net2 bosh-ipv6-acceptance-tests/ci/cloud-config-network.yml \
  -v internal_cidr=10.245.0.0/16 \
  -v internal_gw=10.245.0.1 \
  -v internal_dns="['8.8.8.8']" \
  -v network_name=ipv4-only \
  -v docker_network_name=ipv4-only

echo "-----> `date`: Update runtime config"
bosh -n update-runtime-config bosh-deployment/runtime-configs/dns.yml \
  -o bosh-ipv6-acceptance-tests/ci/local-bosh-dns.yml

echo "-----> `date`: Upload stemcell"
bosh -n upload-stemcell https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-trusty-go_agent?v=3541.9 \
	--sha1 44138ff5e30cc1d7724d88eaa70fab955b8011bd

echo "-----> `date`: Deploy"
bosh -n -d zookeeper deploy <(wget -O- https://raw.githubusercontent.com/cppforlife/zookeeper-release/master/manifests/zookeeper.yml) \
	-o bosh-ipv6-acceptance-tests/ci/zookeeper-enable-dns.yml \
	-o bosh-ipv6-acceptance-tests/ci/zookeeper-two-networks.yml \
  -o bosh-ipv6-acceptance-tests/ci/zookeeper-docker-cpi-disks.yml

echo "-----> `date`: Exercise deployment"
bosh -n -d zookeeper run-errand status
bosh -n -d zookeeper run-errand smoke-tests

echo "-----> `date`: Delete deployment"
bosh -n -d zookeeper delete-deployment

echo "-----> `date`: Clean up disks, etc."
bosh -n -d zookeeper clean-up --all

echo "-----> `date`: Deleting env"
bosh delete-env bosh-deployment/bosh.yml \
  -o bosh-deployment/docker/cpi.yml \
  -o bosh-deployment/jumpbox-user.yml \
  -o bosh-deployment/uaa.yml \
  -o bosh-deployment/credhub.yml \
  -v director_name=ipv4-plus-ipv6 \
  -v internal_cidr=10.245.0.0/16 \
  -v internal_gw=10.245.0.1 \
  -v internal_ip=10.245.0.3 \
  --state state.json \
  --vars-store creds.yml \
  -v director_name=docker \
  -v docker_host=$DOCKER_HOST \
  --var-file docker_tls.ca=${docker_certs_dir}/ca.pem \
  --var-file docker_tls.certificate=${docker_certs_dir}/cert.pem \
  --var-file docker_tls.private_key=${docker_certs_dir}/key.pem \
  -o bosh-ipv6-acceptance-tests/ci/local-bosh-release.yml \
  -o bosh-ipv6-acceptance-tests/ci/local-docker-cpi.yml \
  -v network=ipv4-only
