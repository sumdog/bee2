Bee2
====
Bee2 is an experimental provisioning system for creating and configuring virtual machines with a hosting provider. At the current time, Bee2 only supports Vultr as a provider and Ansible as a provisioning system. Future plans involve having Bee2 support multiple providers, establish VPNs and networking services and host applications via Docker.

Documentation
=============
You can learn more about Bee2 from [my blog post on PenguinDreams](http://penguindreams.org/blog/bee2-wrestling-with-the-vultr-api/).

Installation
============
    gem install --user vultr
    git clone https://github.com/sumdog/bee2

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
    playbook: ubuntu-example.yml
  vpn:
    plan: 201 # 1024 MB RAM,25 GB SSD,1.00 TB BW
    os: 230 # FreeBSD 11 x64
    private_ip: 192.168.150.20
    dns:
      public:
        - vpn.example.com
      private:
        - vpn.example.net
    playbook: freebsd-example.yml
```

Sample configuration can be found in the `examples` folder. The two example Ansible playbooks should be placed in the root of the `ansible` folder.

Usage
=====
    ./bee2 -c settings.yml -p -r -a public

* `-c [config.yml]` specifies the configuration file (required)
* `-p` will provision servers that don't currently exist
* `-r` will delete current servers (to be used with `-p` for rebuilding)
* `-a [public|private]` will run Ansible using either the public or private IPs
