require 'yaml'
require_relative '../lib/dockerhandler'
require 'logger'

log = Logger.new(STDOUT)

RSpec.describe DockerHandler do
  prefix = 'foo2'
  config = <<-CONFIG
  provisioner:
    state_file: spec/test-state.yml
  docker:
    prefix: #{prefix}
  servers:
    web1:
      ipv6:
        docker:
          suffix_bridge: 1:0:0/96
          suffix_net: 2:0:0/96
          static_web: 2:0:a
  security:
    pgp_id: ABCDEFG
  jobs:
    runner:
      server: web1
      env:
        type: task
  applications:
    mail:
      server: web1
      env:
        domains:
          - mail.penguindreams.org
    content-engine:
      server: web1
      db:
        - mysql
    image-poster:
      server: web1
      db:
        - postgres
    cron:
      server: web1
      env:
        run_container: +runner
    certbot:
      server: web1
      env:
        test: false
        domains: all
    nginx-static:
      server: web1
      env:
        domains:
          - dyject.com/80
          - penguindreams.org/9000
          - rearviewmirror.cc
    haproxy:
      server: web1
      ipv6_web: true
      env:
        domains: all
        certbot_container: $certbot
      ports:
        - 80
        - 443
      volumes:
        - letsencrypt:/etc/letsencrypt:rw
        - haproxycfg:/etc/haproxy:rw
        - /var/run/docker.sock:/var/run/docker.sock
    con1:
      server: web1
      env:
        location: Melbourne
    con2:
      server: web2
      env:
        location: Wellington
  CONFIG
  cfg_yaml = YAML.load(config)
  config = DockerHandler.new(cfg_yaml, log, 'web1:test')

  describe "domain mapping" do
    it "returns a list of each container and its domains" do
      domains = config.all_domains
      expect(domains).to contain_exactly(['nginx-static', ['dyject.com/80',
        'penguindreams.org/9000', 'rearviewmirror.cc']], ['mail',['mail.penguindreams.org']])
    end
  end

  describe "state loading" do
    it "loads ipv6 addresses for web containers" do
      expect(config.state['servers']['web1']['ipv6']['static_web']).to eq('a:b:c:d::2:0:a')
    end
    it "no settings for web2" do
      expect(config.state['servers']['web2']).to be_nil
    end
    it "static ipv6 address should match subnet and suffix" do
      expect(config.state['servers']['web1']['ipv6']['static_web']).to eq(
         config.state['servers']['web1']['ipv6']['subnet'] +
         cfg_yaml['servers']['web1']['ipv6']['docker']['static_web']
      )
    end
  end

  describe "container configuration" do
    it "shouldn't use links" do
      r = config.config_to_containers('apps', 'web1', 'nginx-static')
      expect(r["#{prefix}-app-nginx-static"]['container_args']['HostConfig']).not_to have_key('Links')
    end

    it "connect to network" do
      r = config.config_to_containers('apps', 'web1', 'haproxy')
      host_config = r["#{prefix}-app-haproxy"]['container_args']['NetworkingConfig']['EndpointsConfig']
      expect(host_config).to have_key("#{prefix}-network")
    end

    it "mapping with variables in env referencing other app containers" do
      r = config.config_to_containers('apps', 'web1', 'haproxy')
      expect(r["#{prefix}-app-haproxy"]['container_args']['Env']).to include("CERTBOT_CONTAINER=#{prefix}-app-certbot")
    end

    it "mapping with variables in env referencing other job containers" do
      r = config.config_to_containers('apps', 'web1', 'cron')
      expect(r["#{prefix}-app-cron"]['container_args']['Env']).to include("RUN_CONTAINER=#{prefix}-job-runner")
    end

    it "job containers should start with job prefix" do
      r = config.config_to_containers('jobs', 'web1', 'runner')
      expect(r["#{prefix}-job-runner"]['container_args']['Env']).to include("TYPE=task")
    end

    it "mapping with exposed ports" do
      r = config.config_to_containers('apps', 'web1', 'haproxy')
      expect(r["#{prefix}-app-haproxy"]['container_args']['ExposedPorts']).to eq(
        {"80/tcp"=>{}, "443/tcp"=>{}}
      )

      expect(r["#{prefix}-app-haproxy"]['container_args']['HostConfig']['PortBindings']).to eq(
        {"80/tcp"=>[{"HostPort"=>"80"}], "443/tcp"=>[{"HostPort"=>"443"}]}
      )
    end

    it "mapping with volumes" do
      r = config.config_to_containers('apps', 'web1', 'haproxy')
      expect(r["#{prefix}-app-haproxy"]['container_args']['HostConfig']['Binds']).to contain_exactly(
        "letsencrypt:/etc/letsencrypt:rw",
        "haproxycfg:/etc/haproxy:rw",
        "/var/run/docker.sock:/var/run/docker.sock"
      )
    end

    it "mapping all domains" do
      r = config.config_to_containers('apps', 'web1', 'haproxy')
      expect(r["#{prefix}-app-haproxy"]['container_args']['Env']).to include(
        "DOMAINS=#{prefix}-app-mail:mail.penguindreams.org #{prefix}-app-nginx-static:dyject.com/80,penguindreams.org/9000,rearviewmirror.cc"
      )
    end

    it "app configuration local to web1" do
      r = config.config_to_containers('apps', 'web1', 'con1')
      expect(r["#{prefix}-app-con1"]['container_args']['Env']).to contain_exactly(
        "LOCATION=Melbourne"
      )
    end

    it "app configuration local to web2" do
      r = config.config_to_containers('apps', 'web2', 'con2')
      expect(r["#{prefix}-app-con2"]['container_args']['Env']).to contain_exactly(
        "LOCATION=Wellington"
      )
    end

    it "web container with static IPv6 address" do
      r = config.config_to_containers('apps', 'web1', 'haproxy')
      expect(r["#{prefix}-app-haproxy"]['container_args']['NetworkingConfig']['EndpointsConfig']["#{prefix}-network"]['IPAMConfig']['IPv6Address']).to eq('a:b:c:d::2:0:a')
    end

    it "container without a web IPv6 address" do
      r = config.config_to_containers('apps', 'web1', 'nginx-static')
      expect(r["#{prefix}-app-nginx-static"]).to_not have_key('NetworkingConfig')
    end
  end

end
