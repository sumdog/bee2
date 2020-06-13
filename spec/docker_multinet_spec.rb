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
      nosix:
        ipv4: 169.198.10.1
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
        bridge: br10
      anon:
        ipv4: 172.30.0.1
        ipv6: fd00:30:10bb::/48
        masquerade: off
        bridge: br11
      nosix:
        ipv4: 10.9.8.1
      onlysix:
        ipv6: fd00:10:9988::/48
        bridge: br10
    jobs:
      goodjob:
        image: nginx
        networks:
          - public
      secretjob:
        image: apache
        networks:
          - anon
      ujob:
        build_dir: Foo
    applications:
      superbot:
        build_dir: SuperBot
        env:
          production: false
        volumes:
          - data:/someapp
        networks:
          - public
      hiddenbot:
        image: scum/hiddenbot:v1.2
        networks:
          - anon
      disconbot:
        image: foo:lts
      frontendbot:
        image: bee
        networks:
          - public
          - nosix
        ports:
          - 10
          - 4410
NETCONFIG

  cfg_yaml = YAML.load(multi_net)
  config_leo = DockerHandler.new(cfg_yaml, log, 'leaderone:test', MockPassStore.new)
  cfg_nets = config_leo.config_for_networks

  describe "networking mapping" do

    it "adds a network to an applications that requests it" do
      r = config_leo.config_to_containers('apps', 'superbot')
      r_config = r["am-app-superbot"]['container_args']['NetworkingConfig']['EndpointsConfig']
      expect(r_config).to have_key("am-public")

      s = config_leo.config_to_containers('apps', 'hiddenbot')
      s_config = s["am-app-hiddenbot"]['container_args']['NetworkingConfig']['EndpointsConfig']
      expect(s_config).to have_key("am-anon")
    end

    it "adds a network to a job that requests it" do
      r = config_leo.config_to_containers('jobs', 'goodjob')
      r_config = r["am-job-goodjob"]['container_args']['NetworkingConfig']['EndpointsConfig']
      expect(r_config).to have_key("am-public")

      s = config_leo.config_to_containers('jobs', 'secretjob')
      s_config = s["am-job-secretjob"]['container_args']['NetworkingConfig']['EndpointsConfig']
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

    it "adds multiple networks if specified" do
      t = config_leo.config_to_containers('apps', 'frontendbot')
      t_config = t["am-app-frontendbot"]['container_args']['NetworkingConfig']['EndpointsConfig']
      expect(t_config).to have_key("am-public")
      expect(t["am-app-frontendbot"]['additional_networks'].size).to be(1)
      expect(t["am-app-frontendbot"]['additional_networks']).to include("am-nosix")
    end

  end


  describe "network creations" do

    it "creates all user defined networks" do
      expect(cfg_nets.size).to be(4)
    end

    it "correctly enable IPv6" do
      expect(cfg_nets['public']['EnableIPv6']).to be(true)
      expect(cfg_nets['anon']['EnableIPv6']).to be(true)
      expect(cfg_nets['nosix']['EnableIPv6']).to be(false)
      expect(cfg_nets['onlysix']['EnableIPv6']).to be(true)
    end

    it "setups up subnets for each network" do
      expect(cfg_nets['public']['IPAM']['Config'].size).to be(2)
      expect(cfg_nets['public']['IPAM']['Config']).to include({"Subnet" => "fd00:20:10aa::/48"})
      expect(cfg_nets['public']['IPAM']['Config']).to include({"Subnet" => "172.20.0.1"})
      expect(cfg_nets['anon']['IPAM']['Config'].size).to be(2)
      expect(cfg_nets['anon']['IPAM']['Config']).to include({"Subnet" => "fd00:30:10bb::/48"})
      expect(cfg_nets['anon']['IPAM']['Config']).to include({"Subnet" => "172.30.0.1"})
      expect(cfg_nets['nosix']['IPAM']['Config'].size).to be(1)
      expect(cfg_nets['nosix']['IPAM']['Config']).to include({"Subnet" => "10.9.8.1"})
      expect(cfg_nets['onlysix']['IPAM']['Config'].size).to be(1)
      expect(cfg_nets['onlysix']['IPAM']['Config']).to include({"Subnet" => "fd00:10:9988::/48"})
    end

    it "binds to public ipv4 address if defined" do
      expect(cfg_nets['public']['Options']['com.docker.network.bridge.host_binding_ipv4']).to eq('10.20.30.40')
      expect(cfg_nets['anon']['Options']['com.docker.network.bridge.host_binding_ipv4']).to eq('1.2.3.4')
      expect(cfg_nets['nosix']['Options']['com.docker.network.bridge.host_binding_ipv4']).to eq('169.198.10.1')
      expect(cfg_nets['onlysix']['Options']['com.docker.network.bridge.host_binding_ipv4']).to be_nil
    end

    it "corrects enables masquerade" do
      expect(cfg_nets['public']['Options']['com.docker.network.bridge.enable_ip_masquerade']).to eq("false")
      expect(cfg_nets['anon']['Options']['com.docker.network.bridge.enable_ip_masquerade']).to eq("false")
      expect(cfg_nets['nosix']['Options']['com.docker.network.bridge.enable_ip_masquerade']).to be_nil
      expect(cfg_nets['onlysix']['Options']['com.docker.network.bridge.enable_ip_masquerade']).to be_nil
    end

    it "selects the correct bridge" do
      expect(cfg_nets['public']['Options']['com.docker.network.bridge.name']).to eq("br10")
      expect(cfg_nets['anon']['Options']['com.docker.network.bridge.name']).to eq("br11")
      expect(cfg_nets['nosix']['Options']['com.docker.network.bridge.name']).to be_nil
      expect(cfg_nets['onlysix']['Options']['com.docker.network.bridge.name']).to eq("br10")
    end

    it "adds the bound IPv6 Address" do
      s = config_leo.config_to_containers('apps', 'frontendbot')
      expect(s["am-app-frontendbot"]['container_args']['HostConfig']['PortBindings']).to eq(
        {"10/tcp"=>
          [{'HostPort'=>'10'},{'HostPort'=>'10', 'HostIp'=>'a:b:c:d102'}],
        "4410/tcp"=>
          [{'HostPort'=>'4410'},{'HostPort'=>'4410', 'HostIp'=>'a:b:c:d102'}]
        }
      )
    end

  end

end
