#!/usr/bin/env ruby

require 'docker'

class DockerHandler

  def initialize(config, log)
    @log = log
    @config = config

    cert_path = 'conf/docker'

    Docker.url = "https://briton.penguin.im:2376"
    Docker.options = {
      client_cert: File.join(cert_path, 'docker-client.crt'),
      client_key: File.join(cert_path, 'docker-client.pem'),
      ssl_ca_file: File.join(cert_path, 'ca.pem'),
      ssl_verify_peer: false,
      scheme: 'https'
    }

    @log.info(Docker.version)

  end

end
