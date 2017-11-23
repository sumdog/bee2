Bee2
====
Bee2 is an experimental provisioning system for creating and configuring virtual machines with a hosting provider. At the current time, Bee2 only supports Vultr as a provider and Ansible as a provisioning system. It has default Ansible roles for provisioning both Ubuntu based Docker nodes and a FreeBSD OpenVPN gateway. It creates secure passwords, establishes firewalls and creates docker certs/keys for remote administration. Once the servers have been provisioned, bee2 can build and launch Docker containers, run Docker based jobs and has builtin docker files for establishing HAProxy + LetsEncrypt, hosting static content via nginx and backing up/restoring Docker volumes.

Documentation
=============
You can learn more about Bee2 from the following posts:

* Part 1: [Bee2: Wrestling with the Vultr API](http://penguindreams.org/blog/bee2-wrestling-with-the-vultr-api/)
* Part 2: [Bee2: Creating a Small Infrastructure for Docker Apps](http://penguindreams.org/blog/bee2-creating-a-small-infrastructure-for-docker-apps/)
* Part 3: [Bee2: Automating HAProxy and LetsEncrypt with Docker](http://penguindreams.org/bee2-automating-haproxy-and-letsencrypt-with-docker/)


Installation
============
    git clone https://github.com/sumdog/bee2
    bundle install

Non-Ruby Dependencies:
  * pwgen
  * ansible >= 2.4.0

Configuration
=============
```
provisioner:
  type: vultr
  token: InsertValidAPIKeyHere
  region: LAX
  state_file: vultr-state.yml
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
docker:
  prefix: bee2
  read_timeout: 900
  backup:
    web1:
      storage_dir: /media/backups
      volumes:
        - letsencrypt
        - logs-web
jobs:
  dyject:
    server: web1
    git: git@github.com:/sumdog/dyject_web.git
    volumes:
      - dyject-web:/dyject/build:rw
applications:
  certbot:
    server: web1
    build_dir: CertBot
    volumes:
      - letsencrypt:/etc/letsencrypt:rw
      - /var/run/docker.sock:/var/run/docker.sock
    env:
      email: blackhole@example.com
      test: false
      domains: all
      port: 8080
      haproxy_container: $haproxy
  nginx-static:
    server: web1
    build_dir: NginxStatic
    env:
      domains:
        - dyject.com
      http_port: 8080
    volumes:
      - dyject-web:/www/dyject.com:ro
      - logs-web:/var/log/nginx:rw
  haproxy:
    server: web1
    build_dir: HAProxy
    env:
      domains: all
      certbot_container: $certbot
    link:
      - nginx-static
      - certbot
    volumes:
      - letsencrypt:/etc/letsencrypt:rw
    ports:
      - 80
      - 443
```

Sample configuration can be found in the `examples` folder.

Usage
=====
    ./bee2 -c settings.yml -p -r -a public -d <docker_command>

* `-c [config.yml]` specifies the configuration file (required)
* `-p` will provision servers that don't currently exist
* `-r` will delete current servers (to be used with `-p` for rebuilding)
* `-a [public|private]` will run Ansible using either the public or private IPs
* `-d` runs commands against a docker server (run `-d help` for more information)

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

Bee2 can now build/rebuild docker containers, run jobs or backup and restore volumes. Using the configuration above, the following with start a container for HAProxy, CertBot (LetsEncrypt) and Nginx, run jobs to populate the static websites and backup the docker volumes:

```
./bee2 -c conf/settings.yml -d web1:build
./bee2 -c conf/settings.yml -d web1:run
./bee2 -c conf/settings.yml -d web1:backup
```

Rebuilding a specific application or running a specific job can be done like so:

```
./bee2 -c conf/settings.yml -d web1:rebuild:haproxy
./bee2 -c conf/settings.yml -d web1:run:dyject
```

Rebuilding the entire infrastructure can be done like so:

```
./bee2 -c conf/settings.yml -p -r
./bee2 -c conf/settings.yml -a public

# Update OpenVPN with the new keys
sudo cp conf/openvpn/* /etc/openvpn

# Restart OpenVPN (varies per Linux distribution)
sudo systemctl restart openvpn.service # systemd restart
sudo /etc/init.d/openvpn restart       # sysvinit restart
sudo sv restart openvpn                # runit restart

# Docker commands to restore state and rebuild containers

./bee2 -c conf/settings.yml -d web1:restore
./bee2 -c conf/settings.yml -d web1:build
./bee2 -c conf/settings.yml -d web1:run
```

For a full list of Docker commands, run `./bee2 -c conf/settings.yml -d help`.
