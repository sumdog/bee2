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
        public:
          ipv4: 172.20.0.1
          ipv6: fd00:20:10aa::/48
          bridge: pub10
        other:
          ipv4: 182.20.0.1
          ipv6: fd80:20:10aa::/48
          bridge: oth10
      applications:
        nginx_single_host:
          networks:
            - public
          build_dir: NginxStatic
          labels:
            lb.net: public
          traefik:
            http:
              hosts:
                - example.com
              port: 8181
              tls: enabled
        nginx_multi_host:
          networks:
            - other
          build_dir: NginxStatic
          labels:
            lb.net: other
          traefik:
            http:
              hosts:
                - my.style
                - www.my.style
              port: 8080
              tls: enabled
        nginx_no_tls:
          networks:
            - other
          build_dir: NginxStatic
          labels:
            lb.net: other
          traefik:
            http:
              hosts:
                - no.ssl
                - www.no.ssl
              port: 8282
CONFIG
cfg_yaml = YAML.load(config)
config_nginx_single_host = DockerHandler.new(cfg_yaml, log, 'serverone:test', MockPassStore.new)


  describe 'traefix lables for secure http service' do
     it 'creates correct labels for a service with a single host with tls enabled' do
       t = config_nginx_single_host.config_to_containers('apps', 'nginx_single_host')
       labels = t['tra-app-nginx_single_host']['container_args']['Labels']
       expect(labels).to eq({'lb.net' => 'public',
                             'traefik.http.routers.tra-app-nginx_single_host.rule' => 'Host(`example.com`)',
                             'traefik.http.services.tra-app-nginx_single_host.loadbalancer.server.port' => '8181',
                             'traefik.http.routers.tra-app-nginx_single_host.entrypoints' => 'websecure',
                             'traefik.http.routers.tra-app-nginx_single_host.tls.certresolver' => 'lec'
                            })
     end
     it 'creates correct labels for a service with multiple hosts' do
       t = config_nginx_single_host.config_to_containers('apps', 'nginx_multi_host')
       labels = t['tra-app-nginx_multi_host']['container_args']['Labels']
       expect(labels).to eq({'lb.net' => 'other',
                             'traefik.http.routers.tra-app-nginx_multi_host.rule' => 'Host(`my.style`,`www.my.style`)',
                             'traefik.http.services.tra-app-nginx_multi_host.loadbalancer.server.port' => '8080',
                             'traefik.http.routers.tra-app-nginx_multi_host.entrypoints' => 'websecure',
                             'traefik.http.routers.tra-app-nginx_multi_host.tls.certresolver' => 'lec'
                            })
     end
     it 'creates correct labels for a service without tls' do
       t = config_nginx_single_host.config_to_containers('apps', 'nginx_no_tls')
       labels = t['tra-app-nginx_no_tls']['container_args']['Labels']
       expect(labels).to eq({'lb.net' => 'other',
                             'traefik.http.routers.tra-app-nginx_no_tls.rule' => 'Host(`no.ssl`,`www.no.ssl`)',
                             'traefik.http.services.tra-app-nginx_no_tls.loadbalancer.server.port' => '8282'
                            })
     end
  end
end
