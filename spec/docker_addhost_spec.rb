require 'yaml'
require_relative '../lib/dockerhandler'
require 'logger'
require 'mocks.rb'

log = Logger.new(STDOUT)

RSpec.describe DockerHandler do
  config = <<-CONFIG
  provisioner:
    state_file: spec/test-state.yml
  docker:
    serverone:
      prefix: tra
      applications:
        service_with_custom_hostname:
          build_dir: Foo
          hostname: special_snowflake

CONFIG
cfg_yaml = YAML.load(config)
config = DockerHandler.new(cfg_yaml, log, 'serverone:test', MockPassStore.new)
  describe 'service with custom container hostname' do
    it 'has special_snowflake as container hostname' do
      r = config.config_to_containers('apps', 'service_with_custom_hostname')
      expect(r['tra-app-service_with_custom_hostname']['container_args']['Hostname']).to eq('special_snowflake')
    end
  end

  # describe 'service without special permissions' do
  #   it 'has no cap permissions' do
  #     r = config.config_to_containers('apps', 'service_without_special')
  #     expect(r['tra-app-service_without_special']['container_args']['HostConfig']['CapAdd']).to be_nil
  #   end
  # end

  # describe 'service with multiple special permissions' do
  #   it 'has list of caps' do
  #     r = config.config_to_containers('apps', 'service_with_multi_special')
  #     expect(r['tra-app-service_with_multi_special']['container_args']['HostConfig']['CapAdd']).to eq(['NET_ADMIN', 'SYS_ADMIN'])
  #   end
  # end

end
