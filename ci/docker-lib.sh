#!/bin/bash

set -e

function generate_certs() {
  certs_dir="$1"

  pushd "${certs_dir}" > /dev/null
    cat <<EOF > ./bosh-vars.yml
---
variables:
- name: docker_ca
  type: certificate
  options:
    is_ca: true
    common_name: ca
- name: docker_tls
  type: certificate
  options:
    extended_key_usage: [server_auth]
    common_name: "$OUTER_CONTAINER_IP"
    alternative_names: ["$OUTER_CONTAINER_IP"]
    ca: docker_ca
- name: client_docker_tls
  type: certificate
  options:
    extended_key_usage: [client_auth]
    common_name: "$OUTER_CONTAINER_IP"
    alternative_names: ["$OUTER_CONTAINER_IP"]
    ca: docker_ca
EOF

   bosh int ./bosh-vars.yml --vars-store=./certs.yml
   bosh int ./certs.yml --path=/docker_ca/ca > ./ca.pem
   bosh int ./certs.yml --path=/docker_tls/certificate > ./server-cert.pem
   bosh int ./certs.yml --path=/docker_tls/private_key > ./server-key.pem
   bosh int ./certs.yml --path=/client_docker_tls/certificate > ./cert.pem
   bosh int ./certs.yml --path=/client_docker_tls/private_key > ./key.pem
  popd > /dev/null
}

function sanitize_cgroups() {
  mkdir -p /sys/fs/cgroup
  mountpoint -q /sys/fs/cgroup || \
    mount -t tmpfs -o uid=0,gid=0,mode=0755 cgroup /sys/fs/cgroup

  mount -o remount,rw /sys/fs/cgroup

  sed -e 1d /proc/cgroups | while read sys hierarchy num enabled; do
    if [ "$enabled" != "1" ]; then
      # subsystem disabled; skip
      continue
    fi

    grouping="$(cat /proc/self/cgroup | cut -d: -f2 | grep "\\<$sys\\>")"
    if [ -z "$grouping" ]; then
      # subsystem not mounted anywhere; mount it on its own
      grouping="$sys"
    fi

    mountpoint="/sys/fs/cgroup/$grouping"

    mkdir -p "$mountpoint"

    # clear out existing mount to make sure new one is read-write
    if mountpoint -q "$mountpoint"; then
      umount "$mountpoint"
    fi

    mount -n -t cgroup -o "$grouping" cgroup "$mountpoint"

    if [ "$grouping" != "$sys" ]; then
      if [ -L "/sys/fs/cgroup/$sys" ]; then
        rm "/sys/fs/cgroup/$sys"
      fi

      ln -s "$mountpoint" "/sys/fs/cgroup/$sys"
    fi
  done
}

function start_docker() {
  certs_dir="$1"
  generate_certs $certs_dir

  mkdir -p /var/log
  mkdir -p /var/run
  sanitize_cgroups

  # check for /proc/sys being mounted readonly, as systemd does
  if grep '/proc/sys\s\+\w\+\s\+ro,' /proc/mounts >/dev/null; then
    mount -o remount,rw /proc/sys
  fi

  local mtu=$(cat /sys/class/net/$(ip route get 8.8.8.8|awk '{ print $5 }')/mtu)
  local server_args="--mtu ${mtu} --host 0.0.0.0:4243 --tlsverify --tlscacert=${certs_dir}/ca.pem --tlscert=${certs_dir}/server-cert.pem --tlskey=${certs_dir}/server-key.pem --data-root /scratch/docker"

  docker daemon ${server_args} >/tmp/docker.log 2>&1 &
  echo $! > /tmp/docker.pid

  sleep 1

  export DOCKER_TLS_VERIFY=1
  export DOCKER_CERT_PATH=$1

  echo "Docker env useful for copy-pasta during debugging"
  env | grep DOCKER_ | xargs -n1 echo export

  rc=1
  for i in $(seq 1 100); do
    echo waiting for docker to come up...
    set +e
    docker info
    rc=$?
    set -e
    if [ "$rc" -eq "0" ]; then
        break
    fi
    sleep 1
  done

  if [ "$rc" -ne "0" ]; then
    exit 1
  fi

  echo $certs_dir
}
