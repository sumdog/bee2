# Bee2

[![Build Status](https://travis-ci.org/sumdog/bee2.svg?branch=master)](https://travis-ci.org/sumdog/bee2)

<img align="right" width="200" src="https://penguindreams.org/images/airwhale-600px.jpg">

Bee2 is an experimental provisioning system for creating and configuring virtual machines with a hosting provider. At the current time, Bee2 only supports Vultr as a provider and Ansible as a provisioning system. It has default Ansible roles for provisioning Ubuntu based Docker nodes, OpenBSD e-mail servers and a FreeBSD OpenVPN gateway. It creates secure passwords with PGP keys, establishes firewalls and creates docker certs/keys for remote administration. Once the servers have been provisioned, bee2 can build and launch Docker containers, run Docker based jobs and has builtin docker files for establishing HAProxy + LetsEncrypt, and hosting static content via nginx.

# Use and Design Documentation

You can learn more about how I designed and wrote Bee2 from the following posts:

* Part 1: [Bee2: Wrestling with the Vultr API](http://penguindreams.org/blog/bee2-wrestling-with-the-vultr-api/)
* Part 2: [Bee2: Creating a Small Infrastructure for Docker Apps](http://penguindreams.org/blog/bee2-creating-a-small-infrastructure-for-docker-apps/)
* Part 3: [Bee2: Automating HAProxy and LetsEncrypt with Docker](http://penguindreams.org/blog/bee2-automating-haproxy-and-letsencrypt-with-docker/)
* Part 4: [Bee2 In Production: IPv6, HAProxy and Docker](https://penguindreams.org/blog/bee2-in-production-ipv6-haproxy-and-docker/)


# Installation

    git clone https://github.com/sumdog/bee2
    bundle install

Non-Ruby Dependencies:
  * pwgen
  * ansible >= 2.4.0

# Configuration

Create a directory called `conf` in the `bee2` root folder. In that folder you will create a settings YAML file. All files referenced within the settings file are relative to the `conf` directory.

There are 9 major configuration sections:

  * Provisioner
  * Inventory
  * Servers
  * OpenVPN
  * Security
  * Sync
  * Docker
    * Jobs
    * Applications

## Provisioners

The `provisioner` section establishes which hosting provider to use and the default region where servers should be created. It also lists a `state_file` which stores information about the provisioning process in YAML, as well as the location for SSH keys.

### Vultr:

```
provisioner:
  type: vultr
  token: InsertValidAPIKeyHere
  region: LAX
  state_file: vultr-state.yml
  ssh_key:
    public: vultr-key.pub
    private: vultr-key
```

### Digital Ocean

(coming soon)

### Name.com

```
provisioner:
  type: name
  api_key: 0000000000000000000000000
  username: your_username
servers:
  bigsense:
    ip:
      private: 10.10.99.1
      public: 93.184.216.34
      gdns: 8.8.8.8
    dns:
      public:
        - example.com
        - www.exmaple.com
        - example.net
      private:
        - internal.example.com
      gdns:
        - dns.example.com
```

The `name` provisioner can be used to setup DNS using the [Name.com API](https://www.name.com/api-docs/). It only handles DNS records. Other commands used with the `name` provisioner configuration assume that VPN and docker connectivity have been setup manually. The provisioner will go through ever record set in the `dns` sections for each server and set them to the A/ipv4 record defined in the `ip` section for that server. Existing records will be updated. IPv6/AAAA records are currently not supported for the `name` provisioner.

## Inventory

The `inventory` section describes the location of the public and private Ansible inventory files. The public inventory is intended to be used when the server is first provisioned. Once Ansible roles have been run for establishing VPNs and Firewalls, the private inventory can be used for running commands via a VPN connection.

```
inventory:
  public: vultr.pub.inv
  private: vultr.pri.inv
```

## Servers

The `servers` section defines every virtual machine that should be provisioned. For a server on Vultr, each server will need a `plan` and `os` section. A private IP address and DNS records records can be defined in this section as well.

Anything defined in the `web` section for DNS will have a `www` record provisioned for it as well as a base record. The `HAProxySetup` and `NginxStatic` containers work together to configure both SSL redirects and redirects from `www` to the base domain.

An Ansible playbook can be defined as well. If configuring the host to run Docker containers, [IPv6 will need to be segmented for the Docker daemon](https://penguindreams.org/blog/bee2-in-production-ipv6-haproxy-and-docker). DNS provisioning will create records for a Docker container that has `ipv6_web` set to `true` (typically the `HAProxy` container).

### Ubuntu Web Server with Docker Containers Example

```
servers:
  web1:
    plan: 202 # 2048 MB RAM,40 GB SSD,2.00 TB BW
    os: 241 # Ubuntu 17.04 x64
    private_ip: 10.10.6.10
    ipv6:
      docker:
        suffix_bridge: 1:0:0/96
        suffix_net: 2:0:0/96
        static_web: 2:0:a
    dns:
      public:
        - web1.example.com
      private:
        - web1.internal.example.net
      web:
        - rearviewmirror.cc
        - battlepenguin.com
        - penguindreams.org
    playbook: docker-web.yml
```

### FreeBSD Server for OpenVPN Example

The included example FreeBSD Ansible playbook will establish a VPN server, generate keys for all the listed clients in the `openvpn` section, place them within `conf/opvn-clients` and create the appropriate DNS records.

```
servers:
  bastion:
    plan: 201 # 1024 MB RAM,25 GB SSD,1.00 TB BW
    os: 230 # FreeBSD 11 x64
    private_ip: 10.10.6.20
    dns:
      public:
        - bastion.example.com
      private:
        - bastion.internal.example.net
    playbook: freebsd-vpn.yml
```

### OpenBSD E-Mail Server Example

The included example OpenBSD Ansible playbook will create an e-mail server using the following stack: OpenSMTPD -> SpamPD (spamassassin) -> ClamAV -> Procmail -> Dovecot. Outgoing e-mail will be signed with a DKIM key. DNS MX records will be established for all listed domains, including DKIM records which come for the specified file. Passwords for e-mail users must manually be set on the server once it has been provisioned.

```
servers:
  bsdmail:
    plan: 201 # 1024 MB RAM,25 GB SSD,1.00 TB BW
    os: 234 # OpenBSD 6 x64
    private_ip: 10.10.6.30
    dns:
      public:
        - bsdmail.example.com
      private:
        - bsdmail.internal.example.net
    mail:
      mx: mail.example.com
      dkim_private: conf/dkim.key
      spf: v=spf1 mx ~all
      dmarc: v=DMARC1; p=reject; rua=dmarc@example.com; ruf=mailto:dmarc@example.com
      cert_email: notify@example.com
      domains:
        - penguindreams.org
        - battlepenguin.com
        - example.com
        - example.net
      users:
        djsumodg:
          - sumdog@example.com
          - sumdog@example.net
        serviceAccount:
          - notifications@penguindreams.org
    playbook: openbsd-mail.yml
```

### Ubuntu Docker Web Server in Alternative Region

The following is an example of a virtual machine provisioned in another data center region (`EWR`) and configured to be a Docker based web server. It connects to the primary data center via OpenVPN.

```
servers:
  leaf:
    plan: 202
    os: 270 # Ubuntu 18.04 x64
    region: EWR
    private_ip: 10.10.12.100
    vpn: bastion.example.com
    ipv6:
      docker:
        suffix_bridge: 1:0:0/96
        suffix_net: 2:0:0/96
        static_web: 2:0:a
    dns:
      public:
        - leaf.example.com
      private:
        - leaf.internal.example.net
      web:
        - hitchhiker.social
    playbook: docker-web-vpnclient.yml
```

## OpenVPN

Servers configured with the OpenVPN Ansible role will use the following settings for provisioning server and client keys. Notice that the `leaf` server we defined above also has its client keys generated via this section.

```
openvpn:
    hosts:
      gateway: 10.10.6.20
    server:
      subnet: 10.10.12.0
      routes:
        - 10.10.6.0 255.255.255.0
      netmask: 255.255.255.0
      cipher: AES-256-CBC
    dnsdomain: internal.example.net
    clients:
      laptop:
        type: host
        ip: 10.10.12.6
      desktop:
        type: host
        ip: 10.10.12.14
      leaf:
        type: host
        ip: 10.10.12.100
```

## Security

The PGP key specified by the following ID will be used to encrypted all root and Docker database container passwords. The generated keys will be stored in `~/.password-store/bee2/[database|server]/...` and can be accessed using the `pass` command.

```
security:
  pgp_id: ACD3453FA23B49CFFD32590BF
```

## Sync

My [photography website](https://journeyofkhan.us) uses a sizable amount of photo storage that needs to be synced to the remote server. The follow section allows for push/rsync directories:

```
sync:
  web1:
    push:
      - /media/bee2-volumes/jok-photos:/media
```
## Docker

Each server that has been configured by the Docker Ansible role can be setup to run containers defined in the `docker` configuration section. With the following configuration, all containers run on `web` will be prefixed with the name `w1` and everything run on `leaf` will have a prefix of `w2`. For example, a container named `haproxy` running on `leaf` will have the container name `w2-app-haproxy`.

```
docker:
  web1:
    prefix: w1
    jobs:
      ...
    applications:
      ...
  leaf:
    prefix: w2
    jobs:
      ...
    applications:
      ...
```

# Usage
    ./bee2 -c settings.yml -p -r -a public[:server] -d <docker_command>

* `-c [config.yml]` specifies the configuration file (required)
* `-p` will provision servers that don't currently exist and create/update DNS records
* `-r` will delete current servers (to be used with `-p` for rebuilding)
* `-a [public|private]` will run Ansible using either the public or private IPs (optional :server)
* `-d` runs commands against a docker server (run `-d help` for more information)

# VPN Client

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

# Connecting Remotely via SSH

Each server will be provisioned to use the SSH key listed in the `provisioner` section of the configuration file. They can be access by specifying the the key file and using the public DNS name before Ansible provisions firewalls or the private DNS once OpenVPN is established.

```
# public

ssh -i /path/to/bee2/conf/vultr-key web1.example.com

# private / openvpn

ssh -i /path/to/bee2/conf/vultr-key web1.internal.example.net

```
# Docker

With the VPN established, you can now remotely access your docker instances via the private DNS name.

    docker --tlsverify --tlscacert=conf/docker/ca.crt  --tlscert=conf/docker/docker-client.crt  --tlskey=conf/docker/docker-client.pem  -H=web1.example.net:2376 version

## Basic Website via Docker

The following is an example for a establishing an HAProxy load balancer along with an Nginx container that will server static web content. Containers can be defined as `jobs` or `applications`. Application containers will build and run in the background while job containers will run and exit. The `JobScheduler` container can be use to launch other job containers at regular intervals.

* Containers must specify either `build_dir`, `image` or `git`.
  * `build_dir` uses the directory found under `dockerfiles` of the bee2 project
  * `git` will check out a project and build the `Dockerfile` located in the base of the repository
     * `branch` optionally selects a repository branch
     * `git_dir` optionally searches for the `Dockerfile` in a subdirectory of the repository
  * `image` will attempt to pull an existing Docker image
* `volumes` indicate volume mappings which can be names or locations on the host file system
* `env` is a list of environment variables that will be passed in as *ALL_CAPS* into the containers.
  * The special `domains` environment variable is a list of domains that map to the container.
  * The special value `domains: all` will pass in a list of domain to container mappings, used by the `HAProxySetup`, `CertBot` and `AWStatsGenerator` containers.
  * Environment variable values that start with `$` will be translated to hostnames for app containers. (e.g. If the prefix is `bee2`, the value `$foo` will be passed to the container as `bee2-app-foo`)
  * Environment variable values that start with '+' will be translated to hostnames for job containers.
* `ports` can be used to specify port mapping for the host machine.

```
docker:
  web1:
    prefix: w1
    jobs:
      web-builder:
        git: git@gitlab.com:djsumdog/web-builder.git
        branch: publish
        volumes:
          - battlepenguin-web:/www/_site/battlepenguin:rw
          - penguindreams-web:/www/_site/penguindreams:rw
      awstats-generate:
        build_dir: AWStatsGenerator
        env:
          username: statsuser
          password: Some1Password
          domains: all
        volumes:
          - awstats:/awstats:rw
          - logs-web:/weblogs:ro
      logrotate:
        build_dir: LogRotate
        env:
          nginx_container: $nginx-static
        volumes:
          - logs-web:/weblogs:rw
          - /var/run/docker.sock:/var/run/docker.sock
      scheduler:
        build_dir: JobScheduler
        env:
          run_logrotate: +logrotate
          when_logrotate: 1 2 */2 * *
          run_awstats: +awstats-generate
          when_awstats: 10 */12 * * *
        volumes:
          - /var/run/docker.sock:/var/run/docker.sock
      hasetup:
        build_dir: HAProxySetup
        env:
          haproxy_container: $haproxy
          certbot_container: $certbot
          awstats_container: $awstats
          domains: all
        volumes:
          - letsencrypt:/etc/letsencrypt:rw
          - haproxycfg:/etc/haproxy:rw
          - /var/run/docker.sock:/var/run/docker.sock
    applications:
      awstats:
        build_dir: AWStatsCGI
        volumes:
          - awstats:/awstats:ro
      certbot:
        build_dir: CertBot
        volumes:
          - letsencrypt:/etc/letsencrypt:rw
          - /var/run/docker.sock:/var/run/docker.sock
        env:
          email: notify@example.com
          test: false
          domains: all
          port: 8080
          haproxy_container: $haproxy
      scheduler:
        build_dir: JobScheduler
        env:
          run_logrotate: +logrotate
          when_logrotate: 1 2 */2 * *
          run_awstats: +awstats-generate
          when_awstats: 10 */12 * * *
        volumes:
          - /var/run/docker.sock:/var/run/docker.sock
      nginx-static:
        build_dir: NginxStatic
        env:
          haproxy_container: $haproxy
          domains:
            - rearviewmirror.cc
            - battlepenguin.com
            - penguindreams.org
          http_port: 8080
        volumes:
          - rvm-web:/www/rearviewmirror.cc:ro
          - battlepenguin-web:/www/battlepenguin.com:rw
          - penguindreams-web:/www/penguindreams.org:rw
          - logs-web:/var/log/nginx:rw
      haproxy:
        image: haproxy:1.8.4
        ipv6_web: true
        volumes:
          - letsencrypt:/etc/letsencrypt:rw
          - haproxycfg:/usr/local/etc/haproxy:rw
        ports:
          - 80
          - 443
```


Bee2 can now build/rebuild docker containers and run jobs. Using the configuration above, the following will run jobs to setup our environment, and then start service containers for HAProxy, CertBot (LetsEncrypt), Nginx, Cron and AWStats.

```
./bee2 -c conf/settings.yml -d web1:run
./bee2 -c conf/settings.yml -d web1:build
```

Rebuilding a specific application or running a specific job can be done like so:

```
./bee2 -c conf/settings.yml -d web1:rebuild:haproxy
./bee2 -c conf/settings.yml -d web1:run:logrotate
```

# Web Applications with Databases

The `DBSetup` container can be used to create users and passwords and setup databases. It generates random password based on the PGP key provided in the `security` section of the configuration. A container which needs a database can specify the `db` attribute and refernce the database container. `DBSetup` will create a user and database for the given container name. Variables prefixed with `_` can be used to inject the generated database password.

```
somewebapp:
  image: somewebapp
  env:
    domains:
      - app.example.com
    db_host: $postgres
    db_name: somewebapp
    db_user: somewebapp
    db_pass: _postgres^password
    db_port: 5432
    db_type: pgsql
    hostname: app.example.com
  db:
    - postgres
```

If two containers need to share a database, it can be specified explicitly like so:

```
somewebapp:
  image: somewebapp
  env:
    domains:
      - app.example.com
    db_host: $postgres
    db_name: somewebapp
    db_user: somewebapp
    db_pass: _postgres:productiondb^password
    db_port: 5432
    db_type: pgsql:productiondb
    hostname: app.example.com
  db:
    - postgres
backend:
  image: somebackend
  env:
    db_host: $postgres
    db_name: somewebapp
    db_user: somewebapp
    db_pass: _postgres:productiondb^password
    db_port: 5432
    db_type: pgsql:productiondb
```

The database container and setup job can be specified like so:

```
jobs:
  dbsetup:
    build_dir: DBSetup
    env:
      database_json: _dbmap
      mysql_host: $mysql
      postgres_host: $postgres
applications:
  postgres:
    image: postgres:10.2
    env:
      postgres_password: _postgres^adminpass
    volumes:
      - postgres:/var/lib/postgresql/data:rw
  mysql:
    image: mysql:5.7.21
    env:
      mysql_root_password: _mysql^adminpass
    volumes:
      - mysql:/var/lib/mysql:rw
```

The special `_dbmap` variable is used to pass a list of database and container mappings for the `DBSetup` container.

# Adding a new Domain or Application

* Add the new domain to the `servers.<server name>.dns.web` section of the server configuration
* Run `bee2 -c conf/settings.yml -p` to have DNS records updated
* Add the application configuration specifying the same domain
* Run `bee2 -c conf/settings.yml -d <server name>:run:dbsetup` to create database
* Run `bee2 -c conf/settings.yml -d <server name>:run:build` to create and start new containers
* Run `bee2 -c conf/settings.yml -d <server name>:run:hasetup` to configure HAProxy for the new domain and containers
* Run `bee2 -c conf/settings.yml -d <server name>:rebuild/certbot` to get and renew LetsEncrypt SSL certificates for the new domain

# Application Examples

These are a few examples based on the dockerfiles contained within Bee2 as well as examples based on official containers. It's a good jumping off point for building your own configurations.

## TTRSS

tt-rss is an open source RSS reader. In the following example, both the web application and the RSS updater are run as service containers, sharing a common database and storage volumes.

```
docker:
  web1:
    applications:
      ttrss:
        build_dir: TTRSS
        env:
          domains:
            - news.example.com
          db_host: $postgres
          db_name: ttrss
          db_user: ttrss
          db_pass: _postgres^password
          db_port: 5432
          db_type: pgsql
          hostname: news.example.com
        db:
          - postgres
        volumes:
          - ttrss-cache:/state:rw
      ttrss-updater:
        build_dir: TTRSSUpdater
        env:
          db_host: $postgres
          db_name: ttrss
          db_user: ttrss
          db_pass: _postgres:ttrss^password
          db_port: 5432
          db_type: pgsql
          hostname: news.example.com
        volumes:
          - ttrss-cache:/state:rw
        db:
          - postgres:ttrss
```

## Roundcube

In the following example, we use the officially supported Roundcube mail container. Since that container defaults to listening on port 80 and the default port cannot be changed, we specify a `/80` on the domain which is processed by the `HAProxySetup` job container when building the haproxy configuration file.

```
docker:
  web1:
    applications:
      webmail:
        image: roundcube/roundcubemail:1.3.6
        env:
          domains:
            - webmail.example.com/80
          roundcubemail_default_host: tls://mail.battlepenguin.com
          roundcubemail_default_port: 143
          roundcubemail_smtp_server: tls://mail.battlepenguin.com
          roundcubemail_smtp_port: 587
          roundcubemail_db_host: $mysql
          roundcubemail_db_user: webmail
          roundcubemail_db_name: webmail
          roundcubemail_db_password: _mysql^password
          roundcubemail_db_type: mysql
        db:
          - mysql
```

## Radicale

Radicale is a self contained server for hosting your own contacts and calendar via the CardDav/CalDav protocols. It doesn't rely on an external database and all the information is stored in the `radicale` volume.

```
radicale:
docker:
  web1:
    applications:
      build_dir: Radicale
      env:
        domains:
          - cal.example.com
      volumes:
        - radicale:/radicale:rw
```

## OpenProject Community Edition

The official OpenProject container does spin up `supervisord` which in turn starts its own postgres and web services. Data can be stored on the volume mount points specified:

```
docker:
  web1:
    applications:
      openproject:
        image: openproject/community:7.4.7
        env:
          domains:
            - project.example.com
          email_delivery_method: smtp
          smtp_address: mail.battlepenguin.com
          smtp_port: 587
          smtp_domain: battlepenguin.com
          smtp_authentication: plain
          smtp_user_name: someuser
          smtp_password: somepassword
          smtp_enable_starttls_auto: true
          secret_key_base: abcdefg1234567890
        volumes:
          - openproject-pgdata:/var/lib/postgresql/9.6/main
          - openproject-logs:/var/log/supervisor
          - openproject-static:/var/db/openproject
```

## Mastodon

Mastodon is a federated and distributed social networking tool. It has an officially supported container, although you need to run that container with slightly different commands for different services. Bee2 contains an `NginxMastodon` container to act as a front end, and supports putting the system in maintenance mode via an environment variable, if it needs to be taken down for updates.

If you intend on running Elastic Search (full text search for toots your instance interacts with), you will need to apply the `linux-es-maxmap` Ansible role to the VM you are running the Elastic Search container on. The `docker-web-vpnclient.yml` playbook currently has this enabled as I use that server for my Mastodon and Elastic Search instances.

We'll need to generate some secrets and keys:

```
# Use the following to generate OTP_SECRET, SECRET_KEY_BASE and PAPERCLIP_SECRET:

OTP_SECRET=$(docker run --rm tootsuite/mastodon:v2.5.0 bundle exec rake secret)
SECRET_KEY_BASE=$(docker run --rm tootsuite/mastodon:v2.5.0 bundle exec rake secret)

# You'll need these keys set in order to generate the VAPID set

docker run --rm -e OTP_SECRET=$OPT_SECRET -e SECRET_KEY_BASE=$KEY_BASE tootsuite/mastodon:v2.5.0 bundle exec rake mastodon:webpush:generate_vapid_key
```

Since we have to reuse the same configuration for multiple containers in Mastodon (web, streaming and sidekiq), I use YAML syntax for referencing a single configuration block.


```
docker:
  kara:
    prefix: social
    mastodon-config: &mastodon_config
      redis_host: $mastodon-redis
      redis_port: 6379
      db_host: $postgres
      db_name: mastodon
      db_user: mastodon
      db_pass: _postgres:mastodon^password
      db_port: 5432
      local_domain: example.com
      local_https: true
      paperclip_secret: <insert generated key from above>
      secret_key_base: <insert generated key from above>
      otp_secret: <insert generated key from above>
      vapid_private_key: <insert generated key from above>
      vapid_public_key: <insert generated key from above>
      smtp_server: mail.example.com
      smtp_port: 587
      smtp_login: mastodon
      smtp_password: somesmtppassword
      smtp_from_address: notifications@example.com
      streaming_cluster_num: 1
      num_days: 15
      es_enabled: true
      es_host: $elasticsearch
      es_port: 9200
    jobs:
      dbsetup:
        build_dir: DBSetup
        env:
          database_json: _dbmap
          postgres_host: $postgres
      mastodon-dbmigrate:
        image: tootsuite/mastodon:v2.5.0
        cmd: bundle exec rake db:migrate
        env: *mastodon_config
        db:
          - postgres:mastodon
      logrotate:
        build_dir: LogRotate
        env:
          nginx_container: $mastodon-nginx
        volumes:
          - logs-web:/weblogs:rw
          - /var/run/docker.sock:/var/run/docker.sock
      hasetup:
        build_dir: HAProxySetup
        env:
          haproxy_container: $haproxy
          certbot_container: $certbot
          domains: all
        volumes:
          - letsencrypt:/etc/letsencrypt:rw
          - haproxycfg:/etc/haproxy:rw
          - /var/run/docker.sock:/var/run/docker.sock
    applications:
      postgres:
        image: postgres:10.2
        env:
          postgres_password: _postgres^adminpass
        volumes:
          - postgres:/var/lib/postgresql/data:rw
      awstats:
        build_dir: AWStatsCGI
        volumes:
          - awstats:/awstats:ro
      scheduler:
        build_dir: JobScheduler
        env:
          run_logrotate: +logrotate
          when_logrotate: 1 2 */2 * *
          run_awstats: +awstats-generate
          when_awstats: 10 */12 * * *
        volumes:
          - /var/run/docker.sock:/var/run/docker.sock
      elasticsearch:
          image: docker.elastic.co/elasticsearch/elasticsearch:6.4.0
          env:
            es_java_opts: -Xms512m -Xmx512m
          volumes:
            - esdata:/usr/share/elasticsearch/data
      mastodon-nginx:
        build_dir: NginxMastodon
        env:
          mastodon_web_container: $mastodon-web
          mastodon_streaming_container: $mastodon-streaming
          maintenance_mode: false
          domains:
            - hitchhiker.social
        volumes:
          - logs-web:/var/log/nginx:rw
      mastodon-redis:
        image: redis:4.0.9-alpine
        volumes:
          - mastodon-redis:/data
      mastodon-streaming:
        image: tootsuite/mastodon:v2.5.0
        cmd: yarn start
        env: *mastodon_config
        db:
          - postgres:mastodon
      mastodon-web:
        image: tootsuite/mastodon:v2.5.0
        cmd: bundle exec rails s -p 3000
        env: *mastodon_config
        db:
          - postgres:mastodon
        volumes:
          - mastodon-system:/mastodon/public/system:rw
      mastodon-sidekiq:
        image: tootsuite/mastodon:v2.5.0
        cmd: bundle exec sidekiq -q default -q mailers -q pull -q push
        env: *mastodon_config
        db:
          - postgres:mastodon
        volumes:
          - mastodon-system:/mastodon/public/system:rw
      certbot:
        build_dir: CertBot
        volumes:
          - letsencrypt:/etc/letsencrypt:rw
          - /var/run/docker.sock:/var/run/docker.sock
        env:
          email: notify@battlepenguin.com
          test: false
          domains: all
          port: 8080
          haproxy_container: $haproxy
      haproxy:
        image: haproxy:1.8.4
        ipv6_web: true
        volumes:
          - letsencrypt:/etc/letsencrypt:rw
          - haproxycfg:/usr/local/etc/haproxy:rw
        ports:
          - 80
          - 443
```

### Starting Mastodon

```
./bee2 -c conf/settings.conf -d web1:run:db-setup
./bee2 -c conf/settings.conf -d web1:run:mastodon-dbmigrate
./bee2 -c conf/settings.conf -d web1:build
```

# Final Thoughts

This README has gotten long and unwieldy. This project was born out of my dissatisfaction for programs like `terraform` and `docker-compose` and I seem to have re-implemented both of them, in one program, for a very specific use case. In retrospect, I wish I had split the Docker tool from the VM provisioning tool, although there is a considerable amount of overlap where they do work better together (e.g. managing DNS records).

Bee2 works very well for how I host my web applications, and it's been a great learning experience. Unfortunately it's not designed to be very general purpose. You may need to fork this project and adjust it to your specific needs if you choose to use it.

I do want to add support for other providers at some point, and may attempt to make it more general purpose in the future. I'd also like to break down the README into a more usable set of documentation. Feel free to file issues or make pull requests.
