require 'yaml'
require_relative '../lib/dockerhandler'
require 'logger'
require 'mocks.rb'

log = Logger.new(STDOUT)

RSpec.describe DockerHandler do
  prefix = 'foo2'
  prefix2 = 'bar3'
  config = <<-CONFIG
  provisioner:
    state_file: spec/test-state.yml
  docker:
    serverone:
      prefix: tra
      networks:
        everything:
          ipv4: 172.100.100.1
          ipv6: fd00:100:10aa::/48
          bridge: eve0
      applications:
        lb_dual_stack:
          networks:
            - everything
          build_dir: Foo
          labels:
            lb.net: everything
          static_ip:
            ipv4: 10.66.55.44.1
            ipv6: fd00:66:55:44:1
        lb_ipv4_stack:
          networks:
            - everything
          build_dir: Foo
          labels:
            lb.net: everything
          static_ip:
            ipv4: 10.55.55.44.1
        lb_ipv6_stack:
          networks:
            - everything
          build_dir: Foo
          labels:
            lb.net: everything
          static_ip:
            ipv6: fd00:77:33:44:1
        daemon_with_additional_hosts:
          networks:
            - everything
          build_dir: Foo
          labels:
            lb.net: everything
          internal_dns:
            example.com: lb_ipv4_stack
            example.su: lb_dual_stack
CONFIG
cfg_yaml = YAML.load(config)
config = DockerHandler.new(cfg_yaml, log, 'serverone:test', MockPassStore.new)

  describe 'static container IP configuration' do
    it 'correctly maps IPv4 only addresses' do
      container_config = config.config_to_containers('apps', 'lb_ipv4_stack')
      ipam = container_config['tra-app-lb_ipv4_stack']['container_args']['NetworkingConfig']['EndpointsConfig']['tra-everything']['IPAMConfig']
      expect(ipam).to eq({"IPv4Address"=>"10.55.55.44.1"})
    end
    it 'correctly maps IPv6 only addresses' do
      container_config = config.config_to_containers('apps', 'lb_ipv6_stack')
      ipam = container_config['tra-app-lb_ipv6_stack']['container_args']['NetworkingConfig']['EndpointsConfig']['tra-everything']['IPAMConfig']
      expect(ipam).to eq({"IPv6Address"=>"fd00:77:33:44:1"})
    end
    it 'correctly maps IPv4/IPv6 dual stack configurations' do
      container_config = config.config_to_containers('apps', 'lb_dual_stack')
      ipam = container_config['tra-app-lb_dual_stack']['container_args']['NetworkingConfig']['EndpointsConfig']['tra-everything']['IPAMConfig']
      expect(ipam).to eq({"IPv4Address"=>"10.66.55.44.1", "IPv6Address"=>"fd00:66:55:44:1"})
    end
  end

  describe 'additional host file configuration' do
    it 'correctly adds additional hosts for IPv4 configurations' do
      container_config = config.config_to_containers('apps', 'daemon_with_additional_hosts')
      extra_hosts = container_config['tra-app-daemon_with_additional_hosts']['container_args']['HostConfig']['ExtraHosts']
      expect(extra_hosts).to containing_exactly('example.com:10.55.55.44.1',
                                                'example.su:10.66.55.44.1',
                                                'example.su:fd00:66:55:44:1')
    end
  end

end
