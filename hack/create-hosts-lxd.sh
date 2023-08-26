#!/bin/bash
set -eux -o pipefail
if [ "$#" -lt 2 ]; then
	echo "Usage: $0 DIR INST..."
	exit 1
fi
dir=$1
shift
names=$*

LXC="sudo lxc"

echo "USER=${USER}"
ssh_config="${dir}/ssh_config"
echo "SSH_CONFIG=${ssh_config}"

# ssh-copy-id wants ~/.ssh to exist
mkdir -p "${HOME}/.ssh"
mkdir -p "${dir}"
prvkey="${dir}/ssh_key"
pubkey="${prvkey}.pub"
if [ ! -e "${pubkey}" ]; then
	ssh-keygen -f "${prvkey}" -q -N ""
fi
echo "IdentityFile ${prvkey}" >"${ssh_config}"

userdata="${dir}/user-data"
if [ ! -e "${userdata}" ]; then
	cat <<EOF >"${userdata}"
#cloud-config
users:
  - name: "${USER}"
    shell: /bin/bash
    ssh-authorized-keys:
      - $(cat "${pubkey}")
  - name: "${USER}-sudo"
    shell: /bin/bash
    ssh-authorized-keys:
      - $(cat "${pubkey}")
    sudo: ALL=(ALL) NOPASSWD:ALL
EOF
fi

for name in ${names}; do
	${LXC} init ubuntu:22.04 "${name}" -c security.privileged=true -c security.nesting=true
	${LXC} config device add "${name}" bind-boot disk source=/boot path=/boot readonly=true
	${LXC} config set "${name}" user.user-data - <"${userdata}"
	${LXC} start "${name}"
	sleep 10
	ip="$(${LXC} exec "${name}" -- ip --json route get 1 | jq -r .[0].prefsrc)"
	echo "Host ${name}" >>"${ssh_config}"
	echo "  Hostname ${ip}" >>"${ssh_config}"
	echo "  # For a test env, the host key can be just ignored"
	echo "  StrictHostKeyChecking=no"
	echo "  UserKnownHostsFile=/dev/null"
	ssh-copy-id -F "${ssh_config}" -i "${prvkey}" -o StrictHostKeyChecking=no "${USER}@${name}"
done
