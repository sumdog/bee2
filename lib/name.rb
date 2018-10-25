require_relative 'provisioner'
require_relative 'util'

class NameProvisioner < Provisioner

  NAME_ENDPOINT = 'https://api.name.com/v4/'

  def initialize(config, log)
    super(config, log)
    @config = config
  end

  def request(method, path, args = {}, ok_lambda = nil, error_code = nil, err_lambda = nil)

    uri = URI.parse("#{NAME_ENDPOINT}/#{path}")
    https = Net::HTTP.new(uri.host, uri.port)
    https.use_ssl = true

    headers = {'Content-Type' => 'application/json'}

    req = case method
    when 'POST'
      r = Net::HTTP::Post.new(uri.path, initheader = headers)
      r.body = args.to_json
      r
    when 'PUT'
      r = Net::HTTP::Put.new(uri.path, initheader = headers)
      r.body = args.to_json
      r
    when 'GET'
      path = "#{uri.path}?".concat(args.collect { |k,v| "#{k}=#{CGI::escape(v.to_s)}" }.join('&'))
      Net::HTTP::Get.new(path, initheader = headers)
    end

    req.basic_auth(@config['provisioner']['username'], @config['provisioner']['api_key'])

    res = https.request(req)

    case res.code.to_i
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

    @config['servers'].each { |server, cfg|
      cfg['dns'].each { |dns_set, domains|
        domains.each { |domain|

          api_call = "domains/#{Util.base_domain(domain)}/records"
          existing = request('GET', api_call)
          cur = existing['records'].select { |r| r['fqdn'] == "#{domain}." }.first
          cur_ip = @config['servers'][server]['ip'][dns_set]
          params = {'host' => Util.host_domain(domain), 'type' => 'A', 'answer' => cur_ip, 'ttl'=>'300'}
          log_msg = "#{cur_ip} :: #{domain}"

          if cur.nil?
            @log.info("Creating #{log_msg}")
            request('POST', api_call, params)
          elsif cur['answer'] == cur_ip
            @log.info("DNS Correct. Skipping #{log_msg}")
          else
            @log.info("Updating #{log_msg}")
            request('PUT', "#{api_call}/#{cur['id']}", params)
          end
        }
      }
    }

  end

end
