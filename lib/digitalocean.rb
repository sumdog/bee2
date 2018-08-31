require_relative 'provisioner'

class DigitalOceanProvisioner < Provisioner

  DO_ENDPOINT = 'https://api.digitalocean.com/v2'

  SSH_KEY_ID = 'b2-provisioner'

  def initialize(config, log)
    super(config, log)
    @config = config
  end

  def ensure_ssh_keys
    ssh_key = File.read(@config['provisioner']['ssh_key']['public'])
    key_list = request('GET', 'account/keys')['ssh_keys'].find { |v| v['name'] == SSH_KEY_ID }
    if key_list.nil? or not key_list.any?
      @log.info("Adding SSH Key #{SSH_KEY_ID}")
      @state['ssh_key_id'] = request('POST', 'account/keys', {'name' => SSH_KEY_ID, 'public_key' =>ssh_key})['ssh_key']['id']
      save_state
    else
      @log.info("SSH key #{SSH_KEY_ID} exists for account")
    end
  end

  def reserve_ips()
    @config['servers'].each { |s,v|
      if @state['servers'].nil?
        @state['servers'] = {}
      end
      if @state['servers'][s].nil?
          @state['servers'][s] = {}
          @state['servers'][s]['ipv4'] = request('POST', 'floating_ips', {
            'region' => @config['provisioner']['region']})['floating_ip']['ip']
          @log.info("Reserved IPs for: #{s} / #{@state['servers'][s]['ipv4']}")
          save_state
      else
        @log.info("IP Already Reserved for: #{s} / #{@state['servers'][s]['ipv4']}")
      end
    }
  end

  def wait_server(server, field, field_value, field_state = true)
    while true
      current_servers = request('GET', 'droplets')['droplets'].map { |d|
        if d['name'] == server
          if (field_state and d[field] != field_value) or (!field_state and d[field] == field_value)
            verb = field_state ? 'have' : 'change from'
            @log.info("Waiting on #{server} to #{verb} #{field} #{field_value}. Current state: #{d[field]}")
            sleep(5)
          else
            @log.info("Complete. Server: #{server} / #{field} => #{field_value}")
            return true
          end
        end
      }
    end
  end

  def ensure_servers
    current_servers = request('GET', 'droplets')['droplets'].map { |k,v| v['name'] }
    create_servers = @state['servers'].keys.reject { |server| current_servers.include? server }
    create_servers.each { |server|
      @log.info("Creating #{server}")
      server_config = {
          'name' => server,
          'region' => @config['provisioner']['region'],
          'size' => @config['servers'][server]['plan'],
          'image' => @config['servers'][server]['os'],
          'ssh_keys' => [@state['ssh_key_id']],
          'ipv6' => true,
          'private_networking' => true
      }

      create_response = request('POST', 'droplets', server_config)['droplet']

      @state['servers'][server]['id'] = create_response['id']
      save_state

      wait_server(server, 'status', 'active')
      @log.info("Assinging floating IP #{@state['servers'][server]['ipv4']} to Server")
      request('POST', "floating_ips/#{@state['servers'][server]['ipv4']}/actions", {'type' => 'assign', 'droplet_id' => create_response['id'] })
    }

  end

  def request(method, path, args = {}, ok_lambda = nil, error_code = nil, err_lambda = nil)

    uri = URI.parse("#{DO_ENDPOINT}/#{path}")
    https = Net::HTTP.new(uri.host, uri.port)
    https.use_ssl = true

    headers = {'Content-Type' => 'application/json',
               'Authorization' => "Bearer #{@config['provisioner']['api_key']}" }

    req = case method
    when 'POST'
      r = Net::HTTP::Post.new(uri.path, initheader = headers)
      r.body = args.to_json
      r
    when 'GET'
      path = "#{uri.path}?".concat(args.collect { |k,v| "#{k}=#{CGI::escape(v.to_s)}" }.join('&'))
      Net::HTTP::Get.new(path, initheader = headers)
    end

    res = https.request(req)

    case res.code.to_i
      # when 503
      #   @log.warn('Rate Limit Reached. Waiting...')
      #   sleep(2)
      #   request(method, path, args, ok_lambda, error_code, err_lambda)
    when 200..299
        if not ok_lambda.nil?
          ok_lambda.()
        else
          if res.body == ''
            ''
          else
            JSON.parse(res.body)
          end
        end
      else
        if not error_code.nil? and res.code.to_i == error_code
          err_lambda.()
        else
          @log.fatal('Error Executing Exoscale Command. Aborting...')
          @log.fatal("#{res.code} :: #{res.body}")
          exit(2)
        end
    end
  end

  def provision(rebuild = false, server = nil)
    ensure_ssh_keys
    reserve_ips
    # populate_ips
    # web_ipv6
    # if rebuild
    #   @log.info('Rebuilding Servers')
    #   delete_provisioned_servers
    # end
    ensure_servers
    # update_dns
    # cleanup_dns
    # mail_dns
    # write_inventory
  end


end
