require 'vultr'
require 'yaml'
require 'logger'

class VultrProvisioner

  SSH_KEY_ID = 'b2-provisioner'

  def initialize(config, log)
    @log = log
    Vultr.api_key = config['provisioner']['token']
    @inventory_files = config['inventory']
    @servers = config['servers']
    @ssh_key = File.read(config['provisioner']['ssh_key']['public'])

    @DCID =  Vultr::Regions.list[:result].find { |id,region|
      region['regioncode'] == config['provisioner']['region']
    }.last['DCID']
    if @DCID.nil?
      @log.fatal("Invalid Data Center #{config['provisioner']['region']}")
      exit 1
    end

    @state_file = config['provisioner']['state-file']
    if File.exists? @state_file
      @state = YAML.load_file(@state_file)
    else
      @state = {}
    end
  end

  private def v(cmd)
    if cmd[:status] != 200
      @log.fatal('Error Executing Vultr Command. Aborting...')
      @log.fatal(cmd)
      exit(2)
    else
      return cmd[:result]
    end
  end

  private def vv(cmd, error_code, ok_lambda, err_lambda)
    case cmd[:status]
    when error_code
      err_lambda.()
    when 200
      ok_lambda.()
    else
      @log.fatal('Error Executing Vultr Command. Aborting...')
      @log.fatal(cmd)
      exit(2)
    end
  end

  def provision(rebuild = false)
    ensure_ssh_keys
    reserve_ips
    populate_ips
    if rebuild
      @log.info('Rebuilding Servers')
      delete_servers
    end
    ensure_servers
    update_dns
    cleanup_dns
    write_inventory

    # Per ticket TTD-04IGO, removing auto assigned IPv6 addresses is impossible via the API
    # remove_unwanted_ips
  end

  def write_inventory
    ['public', 'private'].each { |inv_type|
      inventory_file = @inventory_files[inv_type]
      File.open(inventory_file, 'w') { |pub|
        @log.info("Writing #{inv_type} inventory to #{inventory_file}")
        @servers.each { |server, settings|
          pub.write("[#{server}]\n")
          pub.write(settings['dns'][inv_type].first)
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
    #
    current = v(Vultr::DNS.records({'domain' => r['domain']})).find{ |c| c['type'] == r['type'] and c['name'] == r['name'] }
    if current.nil?
      Vultr::DNS.create_record(r)
      @log.info('Record Created')
    else
      r['RECORDID'] = current['RECORDID']
      Vultr::DNS.update_record(r)
      @log.info('Record Updated')
    end
    #
    # vv(Vultr::DNS.create_record(r), 412, -> {
    #     @log.info('Record Created')
    #   },
    #   ->{
    #     current = v(Vultr::DNS.records({'domain' => r['domain']})).find { |r| r['name'] == r['name'] }
    #     r['RECORDID'] = current['RECORDID']
    #     vv(Vultr::DNS.update_record(r), 412,-> {
    #       @log.info('Record Updated')
    #     },
    #     ->{
    #      @log.info('Record Unchanged')
    #     })
    # })
  end

  # Remove anything set to 127.0.0.1 and MX records
  def cleanup_dns()
    v(Vultr::DNS.list).each {|domain|
      v(Vultr::DNS.records({'domain' => domain['domain']})).each { |record|
        if(record['data'] == '127.0.0.1' or
           (record['type'] == 'MX' and record['data'] == domain['domain']) or
           (record['type'] == 'CNAME' and record['data'] == domain['domain'])
          )
          @log.info("Removing #{record['type']} #{record['name']}.#{domain['domain']}")
          v(Vultr::DNS.delete_record({ 'RECORDID' => record['RECORDID'], 'domain' => domain['domain']}))
        end
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
         when 'private_ip'
            {'domain' => domain, 'name' => s, 'type' => 'A', 'data' => server_config['private_ip']['addr'] }
         when 'web'
            [{'domain' => domain, 'name' => "www.#{s}", 'type' => 'A', 'data' => server_config['ipv4']['addr'] },
            {'domain' => domain, 'name' => "www.#{s}", 'type' => 'AAAA', 'data' => server_config['ipv6']['addr'] }]
         end
      }.flatten.each { |d|
        @log.info("Creating/Updating #{d['name']}.#{d['domain']} #{d['type']} #{d['data']}")
        dns_update_check(d)
      }
    }
  end

  def update_dns
    current_dns = v(Vultr::DNS.list)
    @state['servers'].each { |server, config|
      dns_sets = {"public"=>["ipv4", "ipv6"], "private"=>["private_ip"], "web"=>["ipv4", "ipv6", "web"]}
      dns_sets.each { |ds_type, typ_cfg|
        records = @servers[server]['dns'][ds_type]
        if not records.nil?
          domain_records(records).each { |domain, subdomains|
            vv(Vultr::DNS.records({'domain' => domain}), 412, ->{
                @log.info("Domain #{domain} exists")
                create_subdomains(subdomains, domain, config, typ_cfg)
              }, -> {
                @log.info("No records for #{domain}. Creating Base Record.")
                if ds_type == 'web'
                  ipv4 = @state['servers'][server]['ipv4']['addr']
                  ipv6 = @state['servers'][server]['ipv6']['addr']
                  @log.debug("IP Map: #{server} -> #{ipv4}/#{ipv6}")
                  v(Vultr::DNS.create_domain({'domain' => domain, 'serverip' => ipv4 }))
                  dns_update_check({'domain' => domain, 'name' => '', 'type' => 'AAAA', 'data' => ipv6 })
                  create_subdomains(['www'], domain, config, ['ipv4', 'ipv6'])
                else
                  v(Vultr::DNS.create_domain({'domain' => domain, 'serverip' => '127.0.0.1' }))
                end
                create_subdomains(subdomains, domain, config, typ_cfg)
              })
          }
        end
      }
    }
  end

  def ensure_servers
    current_servers = v(Vultr::Server.list).map { |k,v| v['label'] }
    create_servers = @state['servers'].keys.reject { |server| current_servers.include? server }
    create_servers.each { |server|
       @log.info("Creating #{server}")
       server_config = {'DCID' => @DCID, 'VPSPLANID' => @servers[server]['plan'], 'OSID' => @servers[server]['os'],
             'enable_private_network' => 'yes',
             'enable_ipv6' => 'yes',
             'label' => server, 'SSHKEYID' => @state['ssh_key_id'],
             'hostname' => server, 'reserved_ip_v4' => @state['servers'][server]['ipv4']['subnet'] }
       @log.debug(server_config)
       subid = v(Vultr::Server.create(server_config))['SUBID']
       @state['servers'][server]['SUBID'] = subid
       save_state

       wait_server(server, 'status', 'active')
       wait_server(server, 'server_state', 'ok')

       # Save auto-generated private IP addresses
       v(Vultr::Server.list).each { |k,v|
         if v['label'] == server
           @state['servers'][server]['private_ip'] = {}
           @state['servers'][server]['private_ip']['addr'] = v['internal_ip']
           @log.info("#{server}'s private IP is #{v['internal_ip']}'")
         end
       }
       save_state

       # Attach our Reserved /Public IPv6 Address
       ip = @state['servers'][server]['ipv6']['subnet']
       @log.info("Attaching #{ip} to #{server}")
       vv(Vultr::RevervedIP.attach({'ip_address' => ip, 'attach_SUBID' => subid}), 412, -> {
         @log.info('IP Attached')
       }, -> {
         @log.warn('Unable to attach IP. Rebooting VM')
         v(Vultr::Server.reboot({'SUBID' => subid}))
       })

       # We can only get the full IPv6 address after it's attached to a server
       # IPv4 subnets are their IP addresses, so we'll set that here too
       tst = v(Vultr::Server.list)
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

  def delete_servers
    current_servers = v(Vultr::Server.list).map { |k,v| v['label'] }
    delete_servers = @state['servers'].keys.reject { |server| not current_servers.include? server }
    delete_servers.each { |server|
      @log.info("Deleting #{server}")
      v(Vultr::Server.destroy('SUBID' => @state['servers'][server]['SUBID']))
      while v(Vultr::RevervedIP.list).find { |k,v| v['label'] == server }.last['attached_SUBID']
        @log.info("Waiting on Reserved IP to Detach from #{server}")
        sleep(5)
      end
    }
  end

  ## Per ticket TTD-04IGO, this is currently impossible with the Vultr API
  def remove_unwanted_ips
    v(Vultr::Server.list).each { |s|
      current_s = s[1]
      reserved_ipv6 = @state['servers'][current_s['label']]['ipv6']['addr']
      s[1]['v6_networks'].each { |n|
        if(n['v6_network'] != reserved_ipv6)
          @log.info("Removing automatically assigned IP #{n['v6_network']} from #{current_s['label']}")
          # v(Vultr::RevervedIP.detach({'ip_address' => reserved_ipv6, 'detach_SUBID' => s[0]}))
        end
      }
    }
  end

  def wait_server(server, field, field_value, field_state = true)
    while true
      current_servers = v(Vultr::Server.list).map { |k,v|
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
    key_list = v(Vultr::SSHKey.list).find { |k,v| v['name'] == SSH_KEY_ID }
    if key_list.nil? or not key_list.any?
      @log.info("Adding SSH Key #{SSH_KEY_ID}")
      @state['ssh_key_id'] = v(Vultr::SSHKey.create({'name' => SSH_KEY_ID, 'ssh_key' =>@ssh_key}))['SSHKEYID']
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
          @state['servers'][s]['ipv4'] = v(Vultr::RevervedIP.create({
            'DCID' => @DCID, 'ip_type'=> 'v4', 'label'=> s}))
          @state['servers'][s]['ipv6'] = v(Vultr::RevervedIP.create({
            'DCID' => @DCID, 'ip_type'=> 'v6', 'label'=> s}))
          @log.info("Reserved IPs for: #{s}")
          save_state
      end
    }
  end

  def populate_ips()
    ip_list = v(Vultr::RevervedIP.list())
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

  def save_state()
    File.open(@state_file, 'w') { |f| YAML.dump(@state, f) }
  end

end
