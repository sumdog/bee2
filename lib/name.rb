require_relative 'provisioner'
require_relative 'util'

class NameProvisioner < Provisioner

  NAME_ENDPOINT = 'https://api.name.com/v4/'

  def initialize(config, log)
    super(config, log)
    @config = config
    @domain_records = {}
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
          @log.fatal('Error Executing Name Command. Aborting...')
          @log.fatal("#{res.code} :: #{res.body}")
          exit(2)
        end
    end
  end

  def dns_upsert(domain, name, record_type, data, ttl = 3600)

    dns_api_call = "domains/#{domain}/records"

    if @domain_records[domain].nil?
      @domain_records[domain] = request('GET', dns_api_call)
    end

    cur = @domain_records[domain].fetch('records', {}).select { |r|
      (r['fqdn'] == "#{domain}." or r['fqdn'] == "#{name}.#{domain}.") and r['type'] == record_type
    }.first

    params = {'host' => name, 'type' => record_type, 'answer' => data, 'ttl'=> ttl}
    fqdn = "#{name}.#{domain}".sub(/^[0.]*/, "")
    log_msg = "#{data} :: #{fqdn}"

    if cur.nil?
      @log.info("Creating #{log_msg}")
      request('POST', dns_api_call, params)
    elsif cur['answer'] == data
      @log.info("DNS Correct. Skipping #{log_msg}")
    else
      @log.info("Updating #{log_msg}")
      request('PUT', "#{dns_api_call}/#{cur['id']}", params)
    end
  end


  def mail_dns(server)

    mail_config = @config['servers'][server]['mail']

    dkim_key = OpenSSL::PKey::RSA.new(File.read(mail_config['dkim_private']))
    b64_key = Base64.strict_encode64(dkim_key.public_key.to_der)
    dkim_dns = "k=rsa; t=s; p=#{b64_key}"

    mail_network = mail_config['network']
    mail_ipv4 = @config['servers'][server]['ip'][mail_network]['ipv4']
    mail_ipv6 = @config['servers'][server]['ip'][mail_network]['ipv6']

    mail_config['domains'].each { |domain|
      [
        { 'name' => '', 'type' => 'MX', 'data' => "#{mail_config['mx']}" },
        # { 'name' => 'mail', 'type' => 'A', 'data' => mail_ipv4 },
        # { 'name' => 'mail', 'type' => 'AAAA', 'data' => mail_ipv6 },
        { 'name' => '_dmarc', 'type' => 'TXT', 'data' => "#{mail_config['dmarc']}" },
        { 'name' => 'dkim1._domainkey', 'type' => 'TXT', 'data' => "#{dkim_dns}" },
        { 'name' => '', 'type' => 'TXT', 'data' => "#{mail_config['spf']}" }
      ].each { |d|
        @log.info("Creating/Updating Mail Record #{d['name']} for #{d['domain']} #{d['type']} #{d['data']}")
        dns_upsert(domain, d['name'], d['type'], d['data'])
      }
    }
  end


  def provision(rebuild = false, server = nil)

    @config['servers'].each { |server, cfg|

      mail_dns(server)

      cfg['dns'].each { |dns_set, domains|
        domains.each { |domain|
          {'ipv4':'A', 'ipv6': 'AAAA'}.each { |ipv, record_type|
            ipv = ipv.to_s
            if @config['servers'][server]['ip'][dns_set].include?(ipv)
              cur_ip = @config['servers'][server]['ip'][dns_set][ipv]
              dns_upsert(Util.base_domain(domain), Util.host_domain(domain), record_type, cur_ip)
            else
              @log.warn("No #{ipv} records for #{dns_set}")
            end
          }
        }
      }
    }

  end

end
