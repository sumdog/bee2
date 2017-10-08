Bee2
====
Bee2 is an experimental provisioning system for creating and configuring virtual machines with a hosting provider. At the current time, Bee2 only supports Vultr as a provider and Ansible as a provisioning system. It has default Ansible roles for provisioning both Ubuntu based Docker nodes and a FreeBSD OpenVPN gateway. It creates secure passwords, establishes firewalls and creates docker certs/keys for remote administration.

Documentation
=============
You can learn more about Bee2 from the following posts:

  *[Bee2: Wrestling with the Vultr API](http://penguindreams.org/blog/bee2-wrestling-with-the-vultr-api/)
  *[Bee2: Creating a Docker and VPN system for personal projects](http://penguindreams.org/blog/bee2-creating-a-docker-and-vpn-system-for-personal-projects/)

Installation
============
    git clone https://github.com/sumdog/bee2

Dependencies:
  * pwgen
  * ansible >= 2.3.2

Configuration
=============
```
provisioner:
  type: vultr
  token: InsertValidAPIKeyHere
  region: LAX
  state-file: vultr-state.yml
  ssh_key:
    public: vultr-key.pub
    private: vultr-key
inventory:
  public: vultr.pub.inv
  private: vultr.pri.inv
servers:
  web1:
    plan: 202 # 2048 MB RAM,40 GB SSD,2.00 TB BW
    os: 241 # Ubuntu 17.04 x64
    private_ip: 192.168.150.10
    dns:
      public:
        - web1.example.com
      private:
        - web1.example.net
      web:
        - penguindreams.org
        - khanism.org
    playbook: ubuntu-playbook.yml
  vpn:
    plan: 201 # 1024 MB RAM,25 GB SSD,1.00 TB BW
    os: 230 # FreeBSD 11 x64
    private_ip: 192.168.150.20
    dns:
      public:
        - vpn.example.com
      private:
        - vpn.example.net
    playbook: freebsd-playbook.yml
    openvpn:
        hosts:
          gateway: 192.168.150.20
        server:
          subnet: 10.10.12.0
          routes:
            - 192.168.150.0 255.255.255.0
          netmask: 255.255.255.0
          cipher: AES-256-CBC
        clients:
          laptop: type: host
    security:
        pgp_id: 1ACBD3G
```

Sample configuration can be found in the `examples` folder.

Usage
=====
    ./bee2 -c settings.yml -p -r -a public

* `-c [config.yml]` specifies the configuration file (required)
* `-p` will provision servers that don't currently exist
* `-r` will delete current servers (to be used with `-p` for rebuilding)
* `-a [public|private]` will run Ansible using either the public or private IPs

VPN
===

After running the public provisioner, the firewall will be activated and you'll need to enable an OpenVPN client in order to connect to any of the servers over their private IP addresses. The location of the configuration will vary depending on your Linux distribution, but it will typically be in `/etc/openvpn/` and look like the following:

```
client
dev tun
proto udp
remote vpn.example.com 1194
resolv-retry infinite
nobind
ca /etc/openvpn/ca.crt
cert /etc/openvpn/laptop.crt
key /etc/openvpn/laptop.key
cipher AES-256-CBC
compress lz4-v2
persist-key
persist-tun
status /var/log/openvpn-status.log
log-append /var/log/openvpn.log
```

You will need to copy the key and certs from `conf/opvn-clients/` to `/etc/openvpn` as well. Then start the openvpn service, either via init script or `systemctl` if you're using systemd. You should now be able to ping all your private DNS entries. If not, check your openvpn logs.

Docker
======

With the VPN established, you can now remotely access your docker instances via the private DNS name.

    docker --tlsverify --tlscacert=conf/docker/ca.crt  --tlscert=conf/docker/docker-client.crt  --tlskey=conf/docker/docker-client.pem  -H=web1.example.net:2376 version
