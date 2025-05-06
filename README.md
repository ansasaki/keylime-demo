# keylime-demo
Automation to deploy a Keylime demo

# Instructions

## Create an account in quay.io

This is necessary to download the Keylime verifier and registrar images provided
there.

Then, you can create a token to authenticate to quay.io when using the demo by:

1. Click on your avatar on the upper right corner and `Account Settings`
2. Click on the robot icon (Robot accounts) on the left bar
3. Createa token by clicking on the `Create Robot Account` button on the right
4. After selecting the name for the robot account and a desciption, click on
   `Create robot account` button
5. Select the repositories the robot account will have access (none are required
   for the demo), then click on `Close` button
6. Click on the cog icon on the right of the newly created bot account and `View
   Credentials`
7. Copy the Robot Account token
8. (Recommended) create a podman secret containing your newly created
   authentication token by running:
   ```
   echo -n "<YOUR_ROBOT_TOKEN>" | podman secret create keylimeDemoPassword
   ```

## Create your inventory

Use the provided example `inventory.yml.example` to create your inventory for
the demo:

- Copy the example and rename to `inventory.yml`:
  ```
  cp inventory.yml.example inventory.yml
  ```
- Set your robot quay.io name as the username by replacing `YOUR_USERNAME` with
    your robot account username (it should be something like `username+robot`)
- Set you quay.io registry secret that contains you password by replacing
    `YOUR_SECRET` with the podman secret you created above (e.g.
    `keylimeDemoPassword`)
- Choose a directory where the necessary files will be created for the demo in
    the `demo_dir` fields. The default is `~/keylime_demo`. Beware: the demo
    creates a new VM for each monitored node (by default 2 nodes named `node1`
    and `node2`). The directory where the demo files are stored needs to have
    enough space (normally creating a directory in `/tmp` is **not** a good idea
    because the available space depends on the memory size)
- You can create mode monitored nodes by adding to the `monitored` following the
    model used for `node1` and `node2`. Keep the ansible_host as the node name
    followed by `.demo` domain as we create a virtual network for them and want
    to address the nodes by hostname (e.g. `node1.demo`)

## Run the playbook to create the demo

The demo will download and deploy the Keylime verifier and registrar container
images. For the monitored nodes, the demo will create a new VM for each node,
place them under a virtual NAT network (by default in subnet `192.168.42.0/24`),
setup the firewall for communicaton between guest VMs and host, setup DNS
resolution, and install the Keylime agent in each node, configuring the IPs and
certificates.

The playbook accesses the `localhost` using `ssh`. Make sure the `sshd` service
is running:

```
systemctl start sshd
```

Then, run the playbook:
```
ansible-playbook -i inventory.yml demo.yml --ask-become-pass
```

The `--ask-become-pass` is necessary to prompt for the `sudo` password. It will
be used to setup the network for the demo.

# Details on the changes made by the demo to the controller (local) machine

The demo pulls the Keylime verifier and registrar containers and run it, mapping
the host ports to the container ports for communication. Inside the container,
they are configured to listen to the IP `0.0.0.0`, meaning that they will accept
any incoming requests regardless of the target IP.

The demo also creates a VM for each monitored node using the latest Fedora
Server stable image. The VM is created with UEFI boot and a virtual TPM.

The network configuration is modified in a quasi-temporary manner, meaning that
the few permanent changes are left, but they are benign. In the following
section we will list what is modified and how to undo the changes.

The changes made by the demo playbook are idempotent.

### Virtual bridge network

A virtual bridge network interface is created as part of the demo network
configuration.

The virtual network definition is permanent, but the created network is
destroyed on reboot.

You can check the created network by running:

```
sudo virsh net-list --all
```

By default, a `demo` network is created. To destroy it, run:

```
sudo virsh net-destroy --network demo
```

To undefine it , run:

```
sudo virsh net-undefine --network demo
```

You can also check the virtual bridge interface created by running:

```
ip link show type bridge
```

By default, a virtual interface called `virbr-demo` is created. This interface
is destroyed on reboot or if the `virsh net-destroy --network demo` command is
executed.

#### Enabling the bridge network in qemu

To allow the created virtual network to be used by qemu, the file
`/etc/qemu/bridge.conf` is modified to include the newly created bridge.

This change is persistent.

To revert it, remove the line `allow virbr-demo` from the
`/etc/qemu/bridge.conf` file.

### Firewall

We run the Keylime verifier and registrar services as containers on the host
network, mapping the necessary ports for communication.
Since the monitored nodes are running on VMs under a NAT network, it is
necessary to modify the firewall configuration to allow the requests from inside
the guest VM to reach the service in the host.

This is done my adding a rich rule to the `libvirt` zone in `firewalld`
configuration. This change is temporary and undone on reboot.

The configuration runs the following command to add the rich rule that allows
communication coming from the NAT subnet to the host:

```
sudo firewall-cmd --zone=libvirt --add-rich-rule='
    rule family="ipv4"
        source address="192.168.42.0/24"
        accept'
```

Where the `192.168.42.0/24` is the default virtual NAT network where the
monitored nodes are connected.

### DNS

A `systemd-resolved` configuration is added to forward the hostname
resolution for the `*.demo` domain to the `libvirt` `dnsmasq` instance created
to handle the virtual NAT network.

This is done by running the following commands
```
resolvectl dns virbr-demo 192.168.42.1
resolvectl domain virbr-demo ~demo
```

This change is not permanent and is lost upon reboot. It is necessary to re-run
the playbook to restore this configuration allowing the monitored nodes
hostnames to be resolved by `libvirt` `dnsmasq` instance
