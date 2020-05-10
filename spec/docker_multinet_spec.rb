require 'yaml'
require_relative '../lib/dockerhandler'
require 'logger'

log = Logger.new(STDOUT)

# TODO DRY
class MockPassStore

  def initialize()
  end

  ## rescue GPGME::Error::DecryptFailed upstream for failed passwords
  def get_or_generate_password(folder, name)
    return "passfor:#{folder}:#{name}"
  end

end

RSpec.describe DockerHandler do
  multi_net = <<-NETCONFIG
provisioner:
  state_file: spec/test-state.yml
servers:
  leaderone:
    ip:
      bastion:
        ipv4: 24.25.26.27
        ipv6: a:b:c:d1b
      public:
        ipv4: 10.20.30.40
        ipv6: a:b:c:d102
      anon:
        ipv4: 1.2.3.4
        ipv6: a:b:c:ffe
      private:
        ipv4: 10.10.100.1
docker:
  leaderone:
    prefix: am
    networks:
      public:
        ipv4: 172.20.0.1
        ipv6: fd00:20:10aa::/48
        masquerade: off
      anon:
        ipv4: 172.30.0.1
        ipv6: fd00:20:10aa::/48
        masquerade: off
    jobs:
      goodjob:
        image: nginx
        network: public
      secretjob:
        image: apache
        network: anon
      ujob:
        build_dir: Foo
    applications:
      superbot:
        build_dir: SuperBot
        env:
          production: false
        volumes:
          - data:/someapp
        network: public
      hiddenbot:
        image: scum/hiddenbot:v1.2
        network: anon
      disconbot:
        image: foo:lts
NETCONFIG

  cfg_yaml = YAML.load(multi_net)
  config_leo = DockerHandler.new(cfg_yaml, log, 'leaderone:test', MockPassStore.new)

  describe "networking mapping" do

    it "adds a network to an applications that requests it" do

      r = config_leo.config_to_containers('apps', 'superbot')
      r_config = r["am-public-app-superbot"]['container_args']['NetworkingConfig']['EndpointsConfig']
      expect(r_config).to have_key("am-public")

      s = config_leo.config_to_containers('apps', 'hiddenbot')
      s_config = s["am-anon-app-hiddenbot"]['container_args']['NetworkingConfig']['EndpointsConfig']
      expect(s_config).to have_key("am-anon")
    end

    it "adds a network to a job that requests it" do
      r = config_leo.config_to_containers('jobs', 'goodjob')
      r_config = r["am-public-job-goodjob"]['container_args']['NetworkingConfig']['EndpointsConfig']
      expect(r_config).to have_key("am-public")

      s = config_leo.config_to_containers('jobs', 'secretjob')
      s_config = s["am-anon-job-secretjob"]['container_args']['NetworkingConfig']['EndpointsConfig']
      expect(s_config).to have_key("am-anon")
    end

    it "adds default network for app if none is specified" do
      t = config_leo.config_to_containers('apps', 'disconbot')
      t_config = t["am-app-disconbot"]['container_args']['NetworkingConfig']['EndpointsConfig']
      expect(t_config).to have_key("am-network")
    end

    it "adds default network for job if none is specified" do
      t = config_leo.config_to_containers('jobs', 'ujob')
      t_config = t["am-job-ujob"]['container_args']['NetworkingConfig']['EndpointsConfig']
      expect(t_config).to have_key("am-network")
    end

  end

end
