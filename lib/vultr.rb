require 'yaml'
require 'logger'
require 'net/http'
require 'net/https'
require 'uri'
require 'cgi'
require 'json'
require 'openssl'
require 'base64'
require_relative 'provisioner'

class VultrProvisioner < Provisioner

  SSH_KEY_ID = 'b2-provisioner'

  def initialize(config, log)
    super(config, log)
    @api_key = config['provisioner']['token']
    @inventory_files = config['inventory']
    @servers = config['servers']
    @vpn = config['openvpn']
    @ssh_key = File.read(config['provisioner']['ssh_key']['public'])
    @default_region = config['provisioner']['region']
  end

  def request(method, path, args = {}, ok_lambda = nil, error_code = nil, err_lambda = nil)
    uri = URI.parse("https://api.vultr.com/v1/#{path}")
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
          @log.fatal('Error Executing Vultr Command. Aborting...')
          @log.fatal("#{res.code} :: #{res.body}")
          exit(2)
        end
    end
  end

  def provision(rebuild = false)
    ensure_ssh_keys
    reserve_ips
    populate_ips
    web_ipv6
    if rebuild
      @log.info('Rebuilding Servers')
      delete_provisioned_servers
    end
    ensure_servers
    update_dns
    vpn_dns
    cleanup_dns
    mail_dns
    write_inventory

    # Per ticket TTD-04IGO, removing auto assigned IPv6 addresses is impossible via the API
    # remove_unwanted_ips
  end

  def web_ipv6
    @servers.select { |name, s|
      s['dns'].has_key?('web')
    }.each { |name,cfg|
      if not @state['servers'][name].has_key?('static_web')
        ipv6 = @state['servers'][name]['ipv6']['subnet'] + cfg['ipv6']['docker']['static_web']
        @log.info("Creating IPv6 Web IP #{ipv6} for #{name}")
        @state['servers'][name]['ipv6']['static_web'] = ipv6
      end
    }
    save_state
  end

  def write_inventory
    ['public', 'private'].each { |inv_type|
      inventory_file = @inventory_files[inv_type]
      File.open(inventory_file, 'w') { |pub|
        @log.info("Writing #{inv_type} inventory to #{inventory_file}")
        @servers.each { |server, settings|
          pub.write("[#{server}]\n")
          pub.write(settings['dns'][inv_type].first)
          pub.write(" server_name=#{server}")
          pub.write("\n\n")
        }
      }
    }
  end

  # Convert domian array (from YAML config) to a hash from each base domain to subdomains
  # Input: [ 'something.example.com', 'some.other.example.com', 'example.net', 'somethingelse.example.net', 'example.org' ]
  # Output: { 'example.com' => [ 'something', 'some.other' ], 'example.net' => ['somethingelse'], 'example.org' => [] }
  # special thanks to elomatreb on #ruby/freenode IRC
  private def domain_records(records)
    Hash[records.group_by {|d| d[/\w+\.\w+\z/] }.map do |suffix, domains|
      [suffix, domains.map {|d| d.gsub(suffix, "").gsub(/\.\z/, "") }.reject {|d| d == "" }]
    end]
  end

  private def dns_update_check(r)
    current = request('GET', 'dns/records', {'domain' => r['domain']}).find{ |c| c['type'] == r['type'] and c['name'] == r['name'] and c['data'] == r['data'] }
    msg = "Domain: #{r['domain']}, Name: #{r['name']}, Type: #{r['type']}"
    if current.nil?
      request('POST', 'dns/create_record', r)
      @log.info("Record Created :: #{msg}")
    else
      r['RECORDID'] = current['RECORDID']
      request('POST', 'dns/update_record', r)
      @log.info("Record Updated :: #{msg}")
    end
  end

  # Remove anything set to 127.0.0.1 and MX records
  def cleanup_dns()
    request('GET', 'dns/list').each {|domain|
      request('GET', 'dns/records', {'domain' => domain['domain']}).each { |record|
        if(record['data'] == '127.0.0.1' or
           (record['type'] == 'MX' and record['data'] == domain['domain']) or
           (record['type'] == 'CNAME' and record['data'] == domain['domain'])
          )
          @log.info("Removing #{record['type']} #{record['name']}.#{domain['domain']}")
          request('POST', 'dns/delete_record', { 'RECORDID' => record['RECORDID'], 'domain' => domain['domain']})
        end
      }
    }
  end

  def vpn_dns()
    if not @vpn.nil?
      @log.info("Updating VPN DNS for #{@vpn['dnsdomain']}")

      # TODO: domain creation if it doesn't exist?

      @vpn['clients'].each { |client, cfg|
        dns_update_check({'domain' => @vpn['dnsdomain'], 'name' => client, 'type' => 'A', 'data' => cfg['ip'] })
      }
    end
  end

  def mail_dns()
    @servers.select { |srv, cfg| cfg.key?('mail') }.each { |server, config|

      # reverse DNS
      subid = @state['servers'][server]['SUBID']
      ipv4 = @state['servers'][server]['ipv4']['addr']

      # Get Vult's auto assigned IPv6 Address, and our reserved on
      rec = domain_records([config['mail']['mx']]).first
      request('GET', 'server/list_ipv6', { 'SUBID' => subid })[subid].each { |addrs|
        # This is really hacky. I hate how Vultr assigns you an IPv6 Address you cannot remove.
        # For mail and only mail servers, we create a AAAA records for both of the IPs.

        @log.info("Creating/Updating AAAA mail server record for IPv6 #{addrs['ip']} :: #{rec[1].first}.#{rec[0]} AAAA")
        dns_update_check({'domain' => rec[0], 'name' => rec[1].first, 'type' => 'AAAA', 'data' => addrs['ip'] })

        @log.info("Creating Reverse DNS for Mail records #{addrs['ip']} to #{config['mail']['mx']}")
        request('POST', 'server/reverse_set_ipv6', { 'SUBID' => subid, 'ip' => addrs['ip'], 'entry' => config['mail']['mx']})
      }

      @log.info("Creating/Updating A mail server record for IPv4 #{ipv4} :: #{rec[1].first}.#{rec[0]} ")
      dns_update_check({'domain' => rec[0], 'name' => rec[1].first, 'type' => 'A', 'data' => ipv4 })

      @log.info("Creating Reverse DNS for Mail records #{ipv4} to #{config['mail']['mx']}")
      request('POST', 'server/reverse_set_ipv4', { 'SUBID' => subid, 'ip' => ipv4, 'entry' => config['mail']['mx']})

      dkim_key = OpenSSL::PKey::RSA.new(File.read(config['mail']['dkim_private']))
      b64_key = Base64.strict_encode64(dkim_key.public_key.to_der)
      dkim_dns = "k=rsa; t=s; p=#{b64_key}"

      config['mail']['domains'].each { |domain|
        [
          {'domain' => domain, 'name' => '', 'type' => 'MX', 'data' => config['mail']['mx'], 'priority' => 10 },
          {'domain' => domain, 'name' => '_dmarc', 'type' => 'TXT', 'data' => "\"#{config['mail']['dmarc']}\"" },
          {'domain' => domain, 'name' => 'dkim1._domainkey', 'type' => 'TXT', 'data' => "\"#{dkim_dns}\"" },
          {'domain' => domain, 'name' => '', 'type' => 'TXT', 'data' => "\"#{config['mail']['spf']}\"" }
        ].each { |d|
          @log.info("Creating/Updating Mail Record #{d['name']}.#{d['domain']} #{d['type']} #{d['data']}")
          dns_update_check(d)
        }
      }
    }
  end

  private def create_subdomains(subdomains, domain, server_config, typ_cfg)
    subdomains.each { |s|
      typ_cfg.map { |ip_type|
         case ip_type
         when 'ipv4'
            {'domain' => domain, 'name' => s, 'type' => 'A', 'data' => server_config['ipv4']['addr'] }
         when 'ipv6'
            {'domain' => domain, 'name' => s, 'type' => 'AAAA', 'data' => server_config['ipv6']['addr'] }
          when 'ipv6-web'
             {'domain' => domain, 'name' => s, 'type' => 'AAAA', 'data' => server_config['ipv6']['static_web'] }
         when 'private_ip'
            {'domain' => domain, 'name' => s, 'type' => 'A', 'data' => @servers[s]['private_ip'] }
         when 'web'
            [{'domain' => domain, 'name' => "www.#{s}", 'type' => 'A', 'data' => server_config['ipv4']['addr'] },
            {'domain' => domain, 'name' => "www.#{s}", 'type' => 'AAAA', 'data' => server_config['ipv6']['static_web'] }]
         end
      }.flatten.each { |d|
        @log.info("Creating/Updating #{d['name']}.#{d['domain']} #{d['type']} #{d['data']}")
        dns_update_check(d)
      }
    }
  end

  def update_dns
    current_dns = request('GET', 'dns/list')
    @state['servers'].each { |server, config|
      dns_sets = {"public"=>["ipv4", "ipv6"], "private"=>["private_ip"], "web"=>["ipv4", "ipv6-web", "web"]}
      ipv4 = @state['servers'][server]['ipv4']['addr']
      ipv6 = @state['servers'][server]['ipv6']['addr']
      dns_sets.each { |ds_type, typ_cfg|
        records = @servers[server]['dns'][ds_type]

        if ds_type == 'web'
          ipv6 = @state['servers'][server]['ipv6']['static_web']
        end

        if not records.nil?
          domain_records(records).each { |domain, subdomains|
            request('GET', 'dns/records', {'domain' => domain}, -> {
              @log.info("Domain #{domain} exists")
              if ds_type == 'web'
                  dns_update_check({'domain' => domain, 'name' => '', 'type' => 'A', 'data' => ipv4 })
                  dns_update_check({'domain' => domain, 'name' => '', 'type' => 'AAAA', 'data' => ipv6 })
                  create_subdomains(['www'], domain, config, ['ipv4', 'ipv6-web'])
              end
              create_subdomains(subdomains, domain, config, typ_cfg)
            }, 412, -> {
              @log.info("No records for #{domain}. Creating Base Record.")
              if ds_type == 'web'
                @log.debug("IP Map: #{server} -> #{ipv4}/#{ipv6}")
                request('POST', 'dns/create_domain', {'domain' => domain, 'serverip' => ipv4 })
                dns_update_check({'domain' => domain, 'name' => '', 'type' => 'AAAA', 'data' => ipv6 })
                create_subdomains(['www'], domain, config, ['ipv4', 'ipv6-web'])
              else
                request('POST', 'dns/create_domain', {'domain' => domain, 'serverip' => '127.0.0.1' })
              end
              create_subdomains(subdomains, domain, config, typ_cfg)
            })
          }
        end
      }
    }
  end

  def region_for_server(server)
    regioncode = (not @servers[server]['region'].nil?) ? @servers[server]['region'] : @default_region
    dcid =  request('GET', 'regions/list').find { |id,region|
      region['regioncode'] == regioncode
    }.last['DCID']
    if dcid.nil?
      @log.fatal("Invalid Data Center #{regioncode}")
      exit 1
    end
    dcid
  end

  def ensure_servers
    current_servers = request('GET', 'server/list').map { |k,v| v['label'] }
    create_servers = @state['servers'].keys.reject { |server| current_servers.include? server }
    create_servers.each { |server|
       @log.info("Creating #{server} in Region #{region_for_server(server)}")
       server_config = {'DCID' => region_for_server(server), 'VPSPLANID' => @servers[server]['plan'], 'OSID' => @servers[server]['os'],
             'enable_private_network' => 'yes',
             'enable_ipv6' => 'yes',
             'label' => server, 'SSHKEYID' => @state['ssh_key_id'],
             'hostname' => server, 'reserved_ip_v4' => @state['servers'][server]['ipv4']['subnet'] }
       subid = request('POST', 'server/create', server_config)['SUBID']
       @state['servers'][server]['SUBID'] = subid
       save_state

       wait_server(server, 'status', 'active')
       wait_server(server, 'server_state', 'ok')

       # Attach our Reserved /Public IPv6 Address
       ip = @state['servers'][server]['ipv6']['subnet']
       @log.info("Attaching #{ip} to #{server}")
       request('POST', 'reservedip/attach', {'ip_address' => ip, 'attach_SUBID' => subid}, -> {
         @log.info('IP Attached')
       }, 412, ->{
         @log.warn('Unable to attach IP. Rebooting VM')
         request('POST', 'server/reboot', {'SUBID' => subid})
       })

       # We can only get the full IPv6 address after it's attached to a server
       # IPv4 subnets are their IP addresses, so we'll set that here too
       tst = request('GET', 'server/list')
       srv = tst.map { |subid, s| s }.select { |ss| ss['label'] == server }.first
       srv_v6_net = @state['servers'][server]['ipv6']['subnet']
       ipv6 = srv['v6_networks'].select { |net| net['v6_network'] == srv_v6_net }.first['v6_main_ip']
       @state['servers'][server]['ipv6']['addr'] = ipv6
       @state['servers'][server]['ipv4']['addr'] = srv['main_ip']
       @log.info("Updating IPv6 for #{server} from net/#{srv_v6_net} to IP/#{ipv6}")
       @log.info("Setting IPv4 for #{server} to #{srv['main_ip']}")
       save_state
    }
  end

  private def remove_ssh_key(host_or_ip)
    @log.info("Removing SSH Key for #{host_or_ip}")
    Process.fork do
      exec('ssh-keygen', '-R', host_or_ip)
    end
    Process.wait
  end

  private def delete_server(server)
    @log.info("Deleting #{server}")
    request('POST', 'server/destroy', {'SUBID' => @state['servers'][server]['SUBID']}, -> {
      @log.info("Server #{server} Deleted")

      # SSH Key Cleanup (DNS, private IP, public IPv4/v6)
      ['public', 'private'].each { |dns_type|
        @servers[server]['dns'][dns_type].each { |hostname|
          remove_ssh_key(hostname)
        }
      }
      remove_ssh_key(@servers[server]['private_ip'])
      ['ipv4', 'ipv6'].each { |ip_type|
        remove_ssh_key(@state['servers'][server][ip_type]['addr'])
      }
    }, 412, -> {
      @log.warn("Unable to destory server. Servers cannot be destoryed within 5 minutes of creation")
      @log.warn("Waiting 15 Seconds")
      sleep(15)
      delete_server(server)
    })
  end

  def delete_provisioned_servers
    current_servers = request('GET', 'server/list').map { |k,v| v['label'] }
    delete_servers = @state['servers'].keys.reject { |server| not current_servers.include? server }
    delete_servers.each { |server|
      delete_server(server)
      while request('GET', 'reservedip/list').find { |k,v| v['label'] == server }.last['attached_SUBID']
        @log.info("Waiting on Reserved IP to Detach from #{server}")
        sleep(5)
      end
    }
  end

  def wait_server(server, field, field_value, field_state = true)
    while true
      current_servers = request('GET', 'server/list').map { |k,v|
        if v['label'] == server
          if (field_state and v[field] != field_value) or (!field_state and v[field] == field_value)
            verb = field_state ? 'have' : 'change from'
            @log.info("Waiting on #{server} to #{verb} #{field} #{field_value}. Current state: #{v[field]}")
            sleep(5)
          else
            @log.info("Complete. Server: #{server} / #{field} => #{field_value}")
            return true
          end
        end
      }
    end
  end

  def ensure_ssh_keys
    key_list = request('GET', 'sshkey/list').find { |k,v| v['name'] == SSH_KEY_ID }
    if key_list.nil? or not key_list.any?
      @log.info("Adding SSH Key #{SSH_KEY_ID}")
      @state['ssh_key_id'] = request('POST', 'sshkey/create', {'name' => SSH_KEY_ID, 'ssh_key' =>@ssh_key})['SSHKEYID']
      save_state
    end
  end

  def reserve_ips()
    @servers.each { |s,v|
      if @state['servers'].nil?
        @state['servers'] = {}
      end
      if @state['servers'][s].nil?
          @state['servers'][s] = {}
          @state['servers'][s]['ipv4'] = request('POST', 'reservedip/create', {
            'DCID' => region_for_server(s), 'ip_type'=> 'v4', 'label'=> s})
          @state['servers'][s]['ipv6'] = request('POST', 'reservedip/create', {
            'DCID' => region_for_server(s), 'ip_type'=> 'v6', 'label'=> s})
          @log.info("Reserved IPs for: #{s} in Region #{region_for_server(s)}")
          save_state
      end
    }
  end

  def populate_ips()
    ip_list = request('GET', 'reservedip/list')
    ['ipv4', 'ipv6'].each { |ip_type|
      @servers.each { |s,v|
        if @state['servers'][s][ip_type]['net'].nil?
          ip = ip_list.find { |x,y| x == @state['servers'][s][ip_type]['SUBID'].to_s }
          @state['servers'][s][ip_type]['subnet'] = ip.last['subnet']
          @log.info("Server #{s} Assigned Subnet #{ip.last['subnet']}/#{ip.last['subnet_size']}")
        end
      }
    }
    save_state
  end

end
