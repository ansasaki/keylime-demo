#!/bin/bash

DVD="fedora.iso"
IP="dhcp"
NAME="keylime"
NETWORK_BRIDGE="virbr0"
OS_VARIANT="fedora"
OS_VERSION="-unknown"
OUT_DIR="$(realpath .)"
PASSWORD="keylime"
ROOT_PASSWORD="keylime"
SSH_KEY="$(realpath ~/.ssh/id_rsa.pub)"
USER="admin"

usage() {
    echo "usage: $0 [OPTIONS]"
    echo "Options: "
    echo "    [-a | --address] <IP>             : Set a static IP address (default: 'dhcp')"
    echo "    [-b | --bridge] <NETWORK_BRIDGE>  : Set the network bridge to attach the VM (default: 'virbr0')"
    echo "    [-d | --debug]                    : Print debug messages"
    echo "    [-h | --help]                     : Print this usage message"
    echo "    [-i | --image] <IP>               : Set the installation ISO image (default: 'fedora.iso')"
    echo "    [-k | --ssh-key] <PATH_TO_PUBKEY> : Add the SSH public key to the VM 'authorized_keys' (default: ~/.ssh/id_rsa.pub)"
    echo "    [-n | --name | --vm] <NAME>       : Name of the VM (default: 'keylime')"
    echo "    [-o | --outdir] <OUTPUT_DIR>      : Set the output directory (default: '.')"
    echo "    [-p | --password] <PASSWORD>      : Set the user password (default: 'keylime')"
    echo "    [-r | --root-pw] <ROOT_PASSWORD>  : Set the root user password (default: 'keylime')"
    echo "    [-s | --os] <OS_VARIANT>          : Name of the OS variant (default: 'fedora')"
    echo "    [-u | --user] <USER>              : Add the given user (default: 'admin')"
    echo "    [-v | --version] <OS_VERSION>     : OS version number (default: '-unknown')"
}

debug() {
    if [[ ! -z "${VERBOSE}" ]]; then
        echo "$1"
    fi
}

while [ "$#" -gt 0 ]; do
    arg="$1"

    case $arg in
        -h | --help)
            usage
            exit 0
            ;;
        -a | --address)
            IP="$2"
            shift
            ;;
        -a=* | --address=*)
            IP=$(echo $arg | cut -d '=' -f 2)
            ;;
        -b | --bridge)
            NETWORK_BRIDGE="$2"
            shift
            ;;
        -b=* | --bridge=*)
            NETWORK_BRIDGE=$(echo $arg | cut -d '=' -f 2)
            ;;
        -d | --debug)
            VERBOSE="True"
            ;;
        -i | --image)
            DVD="$2"
            shift
            ;;
        -i=* | --image=*)
            DVD=$(echo $arg | cut -d '=' -f 2)
            ;;
        -k | --ssh-key)
            SSH_KEY="$2"
            shift
            ;;
        -k=* | --ssh-key=*)
            SSH_KEY=$(echo $arg | cut -d '=' -f 2)
            ;;
        -n | --name | --vm)
            NAME="$2"
            shift
            ;;
        -n=* | --name=* | --vm=*)
            NAME=$(echo $arg | cut -d '=' -f 2)
            ;;
        -o | --outdir)
            OUT_DIR="$2"
            shift
            ;;
        -o=* | --outdir=*)
            OUT_DIR=$(echo $arg | cut -d '=' -f 2)
            ;;
        -p | --password)
            PASSWORD="$2"
            shift
            ;;
        -p=* | --password=*)
            PASSWORD=$(echo $arg | cut -d '=' -f 2)
            ;;
        -r | --root-pw)
            ROOT_PASSWORD="$2"
            shift
            ;;
        -r=* | --root-pw=*)
            ROOT_PASSWORD=$(echo $arg | cut -d '=' -f 2)
            ;;
        -s | --os)
            OS_VARIANT="$2"
            shift
            ;;
        -s=* | --os=*)
            OS_VARIANT=$(echo $arg | cut -d '=' -f 2)
            ;;
        -u | --user)
            USER="$2"
            shift
            ;;
        -u=* | --user=*)
            USER=$(echo $arg | cut -d '=' -f 2)
            ;;
        -v | --version)
            OS_VERSION="$2"
            shift
            ;;
        -v=* | --version=*)
            OS_VERSION=$(echo $arg | cut -d '=' -f 2)
            ;;
        *)
            echo "unknown option '$1'"
            usage
        ;;
    esac
    shift
done

echo "Creating VM \"${NAME}\""

debug "Name = ${NAME}"
debug "Image = ${DVD}"
debug "IP = ${IP}"
debug "BRIDGE = ${NETWORK_BRIDGE}"
debug "SSH_KEY = ${SSH_KEY}"
debug "PASSWORD = ${PASSWORD}"
debug "OS_VARIANT = ${OS_VARIANT}"
debug "OS_VERSION = ${OS_VERSION}"
debug "OUT_DIR = ${OUT_DIR}"
debug "ROOT_PASSWORD = ${ROOT_PASSWORD}"
debug "USER = ${USER}"
BASE_DIR="$NAME"

if [[ ! -d "${OUT_DIR}" ]]; then
    # Check that the output directory exists
    echo "The output directory '${OUT_DIR}' does not exist or is not a directory"
    exit 1
fi

CRYPT_PW=$(mkpasswd -m sha-512 ${PASSWORD})
debug "CRYPT_PW = ${CRYPT_PW}"

CRYPT_ROOT_PW=$(mkpasswd -m sha-512 ${ROOT_PASSWORD})
debug "CRYPT_ROOT_PW = ${CRYPT_ROOT_PW}"

if [[ "${IP}" != "dhcp" ]]; then
    debug "Static IP will be set as ${IP}"
    NET="network --onboot=yes --device=link --bootproto static --ip ${IP} --netmask 255.255.255.0 --gateway 192.168.124.1 --nameserver 192.168.124.1 --activate"
else
    debug "Static IP not set"
    NET="network --bootproto=dhcp"
fi

if [[ -n "${SSH_KEY}" ]]; then
    # Check if the file looks like a private key
    if (grep "^-*BEGIN.*PRIVATE" "${SSH_KEY}"); then
        echo "'${SSH_KEY}' does not look like a public SSH key, but a private key. Aborting."
        exit 1
    fi
    # Otherwise check if ss-keygen can parse and find the public key
    if (ssh-keygen -l -f ${SSH_KEY} >> /dev/null); then
        PUB_KEY="$(cat ${SSH_KEY})"
        debug "PUB_KEY=${PUB_KEY}"
    else
        echo "'${SSH_KEY}' does not look like a public SSH key. Aborting."
        exit 1
    fi
fi

cat << EOF > "${OUT_DIR}/${NAME}.ks"
# Language and locale configuration
firstboot --disable
lang en_US.UTF-8
keyboard --xlayouts='us'
timezone America/New_York --utc

# Set root password and create user for management with ansible
rootpw ${CRYPT_ROOT_PW} --iscrypted
user --name ${USER} --password=${CRYPT_PW} --iscrypted

reboot
text
skipx

# Create disks partitions
ignoredisk --only-use=vda
clearpart --all --initlabel --disklabel=gpt --drives=vda
part /boot/efi --size=512 --fstype=efi
part /boot --size=512 --fstype=xfs --label=boot
part / --fstype="xfs" --ondisk=vda --label=root --grow

${NET}
network --hostname=${NAME}

firstboot --disable
selinux --enforcing
firewall --enabled --http --ssh

reboot

%packages
@^server-product-environment
python3-cryptography
%end

%post
LOG_FILE=/root/ks-post.log
[ -n "" ] && LOG_FILE=/dev/null
exec < /dev/tty3 > /dev/tty3
chvt 3
(
    IP="$IP"
    if [ "${IP}" != "dhcp" ]; then
        mkdir -p /etc/NetworkManager/conf.d/
        cat << _EOF >> /etc/NetworkManager/conf.d/00-10mt-static-ip.conf
# File automatically created when setting up a VM with static IP address.
[device]
keep-configuration=no
allowed-connections=except:origin:nm-initrd-generator
_EOF
    fi

    SSH_KEY="$PUB_KEY"
    if [ -n "${PUB_KEY}" ]; then
        # Copy public ssh key.
        mkdir -m0700 -p /root/.ssh/
        echo "${PUB_KEY}" > /root/.ssh/authorized_keys
        chmod 0600 /root/.ssh/authorized_keys
        restorecon -R /root/.ssh/
    fi
    if [ -n "${PUB_KEY}" ]; then
        # Copy public ssh key.
        mkdir -m0700 -p /home/${USER}/.ssh/
        echo "${PUB_KEY}" > /home/${USER}/.ssh/authorized_keys
        chown -R ${USER}:${USER} /home/${USER}/.ssh
        chmod 0600 /home/${USER}/.ssh/authorized_keys
        restorecon -R /home/${USER}/.ssh/
    fi

) 2>&1 | tee "${LOG_FILE}" > /dev/tty3
chvt 1
%end
EOF

# Install the VM using the created kickstart file
virt-install --connect qemu:///session \
    --name ${NAME} \
    --os-variant ${OS_VARIANT}${OS_VERSION} \
    --ram 2048 --vcpus 2 --disk path="${OUT_DIR}/${NAME}.qcow2",size=20,bus=virtio,cache=none,format=qcow2 \
    --location ${DVD} \
    --initrd-inject "${OUT_DIR}/${NAME}.ks" \
    --extra-args "inst.ks=file:/${NAME}.ks disable_ipv6=1 console=tty0 console=ttyS0,115200 rhgb quiet" \
    --nographic \
    --noautoconsole \
    --wait -1 \
    --rng /dev/urandom \
    --tpm backend.type=emulator,backend.version=2.0,model=tpm-tis \
    --console pty,target_type=serial \
    --network bridge=${NETWORK_BRIDGE} \
    --boot uefi
