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
      applications:
        service_with_special:
          build_dir: Foo
          capadd:
            - NET_ADMIN
        service_without_special:
          build_dir: Foo
        service_with_multi_special:
          build_dir: Foo
          capadd:
            - NET_ADMIN
            - SYS_ADMIN
CONFIG
cfg_yaml = YAML.load(config)
config = DockerHandler.new(cfg_yaml, log, 'serverone:test', MockPassStore.new)

  describe 'service with one special permissions' do
    it 'added NET_ADMIN' do
      r = config.config_to_containers('apps', 'service_with_special')
      expect(r['tra-app-service_with_special']['container_args']['HostConfig']['CapAdd']).to eq(['NET_ADMIN'])
    end
  end

  describe 'service without special permissions' do
    it 'has no cap permissions' do
      r = config.config_to_containers('apps', 'service_without_special')
      expect(r['tra-app-service_without_special']['container_args']['HostConfig']['CapAdd']).to be_nil
    end
  end

  describe 'service with multiple special permissions' do
    it 'has list of caps' do
      r = config.config_to_containers('apps', 'service_with_multi_special')
      expect(r['tra-app-service_with_multi_special']['container_args']['HostConfig']['CapAdd']).to eq(['NET_ADMIN', 'SYS_ADMIN'])
    end
  end

end
