class ExoscaleProvisioner

  COMPUTE_ENDPOINT = 'https://api.exoscale.ch/compute'

  DNS_ENDPOINT = 'https://api.exoscale.ch/dns'

  def initialize(config, log)
    @log = log
    @api_key = config['provisioner']['api_key']

  end

  def request(method, path, endpoint = COMPUTE_ENDPOINT, args = {}, ok_lambda = nil, error_code = nil, err_lambda = nil)
    uri = URI.parse("#{endpoint}/#{path}")
    https = Net::HTTP.new(uri.host, uri.port)
    https.use_ssl = true

    req = case method
    when 'POST'
      r = Net::HTTP::Post.new(uri.path, initheader = {'API-Key' => @api_key })
      r.set_form_data(args)
      r
    when 'GET'
      path = "#{uri.path}?".concat(args.collect { |k,v| "#{k}=#{CGI::escape(v.to_s)}" }.join('&'))
      Net::HTTP::Get.new(path, initheader = {'API-Key' => @api_key })
    end

    res = https.request(req)

    case res.code.to_i
      when 503
        @log.warn('Rate Limit Reached. Waiting...')
        sleep(2)
        request(method, path, args, ok_lambda, error_code, err_lambda)
      when 200
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
    puts('Too Expensive. Gave up. Who charges for DNS zones?!')
    # ensure_ssh_keys
    # reserve_ips
    # populate_ips
    # web_ipv6
    # if rebuild
    #   @log.info('Rebuilding Servers')
    #   delete_provisioned_servers
    # end
    # ensure_servers
    # update_dns
    # cleanup_dns
    # mail_dns
    # write_inventory
  end


end
