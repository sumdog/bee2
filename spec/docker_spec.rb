require 'yaml'
require_relative '../lib/dockerhandler'
require 'logger'

log = Logger.new(STDOUT)

RSpec.describe DockerHandler do
  prefix = 'foo2'
  config = <<-CONFIG
  docker:
    prefix: #{prefix}
  security:
    pgp_id: ABCDEFG
  applications:
    mail:
      server: web1
      env:
        domains:
          - mail.penguindreams.org
    content-engine:
      server: web1
      link:
        - nginx-static
      db:
        - mysql
    image-poster:
      server: web1
      db:
        - postgres
    certbot:
      server: web1
      env:
        test: false
        domains: all
    nginx-static:
      server: web1
      env:
        domains:
          - dyject.com
          - penguindreams.org
          - rearviewmirror.cc
    haproxy:
      server: web1
      env:
        domains: all
        certbot_container: $certbot
      link:
        - nginx-static
        - certbot
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
  config = DockerHandler.new(YAML.load(config), log, 'web1:test')

  describe "domain mapping" do
    it "returns a list of each container and its domains" do
      domains = config.all_domains
      expect(domains).to contain_exactly(['nginx-static', ['dyject.com',
        'penguindreams.org', 'rearviewmirror.cc']], ['mail',['mail.penguindreams.org']])
    end
  end

  describe "container configuration" do
    it "mapping without links" do
      r = config.config_to_containers('apps', 'web1', 'nginx-static')
      expect(r["#{prefix}-app-nginx-static"]['container_args']['HostConfig']).not_to have_key('Links')
    end

    it "mapping with links" do
      r = config.config_to_containers('apps', 'web1', 'haproxy')
      host_config = r["#{prefix}-app-haproxy"]['container_args']['HostConfig']
      expect(host_config).to have_key('Links')
      expect(host_config['Links']).to contain_exactly("#{prefix}-app-nginx-static", "#{prefix}-app-certbot")
    end

    it "mapping with variables in env referencing other containers" do
      r = config.config_to_containers('apps', 'web1', 'haproxy')
      expect(r["#{prefix}-app-haproxy"]['container_args']['Env']).to include("CERTBOT_CONTAINER=#{prefix}-app-certbot")
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

    it "mapping with databases" do
      r = config.config_to_containers('apps', 'web1', 'image-poster')
      host_config = r["#{prefix}-app-image-poster"]['container_args']['HostConfig']
      expect(host_config).to have_key('Links')
      expect(host_config['Links']).to contain_exactly("#{prefix}-app-postgres")
    end

    it "mapping with databases and links" do
      r = config.config_to_containers('apps', 'web1', 'content-engine')
      host_config = r["#{prefix}-app-content-engine"]['container_args']['HostConfig']
      expect(host_config).to have_key('Links')
      expect(host_config['Links']).to contain_exactly("#{prefix}-app-nginx-static", "#{prefix}-app-mysql")
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
        "DOMAINS=#{prefix}-app-mail:mail.penguindreams.org #{prefix}-app-nginx-static:dyject.com,penguindreams.org,rearviewmirror.cc"
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
  end

end
