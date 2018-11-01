class Provisioner

  def initialize(config, log)
    @log = log
    @servers = config['servers']
    @inventory_files = config['inventory']

    if(config['provisioner'].has_key?('state_file'))
      @state_file = config['provisioner']['state_file']
      if File.exists? @state_file
        @state = YAML.load_file(@state_file)
      else
        @state = {}
      end
    end

  end

  # Convert domian array (from YAML config) to a hash from each base domain to subdomains
  # Input: [ 'something.example.com', 'some.other.example.com', 'example.net', 'somethingelse.example.net', 'example.org' ]
  # Output: { 'example.com' => [ 'something', 'some.other' ], 'example.net' => ['somethingelse'], 'example.org' => [] }
  # special thanks to elomatreb on #ruby/freenode IRC
  def domain_records(records)
    Hash[records.group_by {|d| d[/\w+\.\w+\z/] }.map do |suffix, domains|
      [suffix, domains.map {|d| d.gsub(suffix, "").gsub(/\.\z/, "") }.reject {|d| d == "" }]
    end]
  end

  def create_subdomains(subdomains, domain, server_config, typ_cfg)
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

  def list_domain_records(domain, ok_func, err_func)
    @log.error("Unimplemented domain_records function")
    exit 2
  end

  def create_domain(domain, ip)
    @log.error("Unimplemented create_domain function")
    exit 2
  end

  def dns_update_check(r)
    @log.error("Unimplemented dns_update_check function")
    exit 2
  end

  def update_dns
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
            list_domain_records(domain, -> {
              @log.info("Domain #{domain} exists")
              if ds_type == 'web'
                  dns_update_check({'domain' => domain, 'name' => '', 'type' => 'A', 'data' => ipv4 })
                  dns_update_check({'domain' => domain, 'name' => '', 'type' => 'AAAA', 'data' => ipv6 })
                  create_subdomains(['www'], domain, config, ['ipv4', 'ipv6-web'])
              end
              create_subdomains(subdomains, domain, config, typ_cfg)
            }, -> {
              @log.info("No records for #{domain}. Creating Base Record.")
              if ds_type == 'web'
                @log.debug("IP Map: #{server} -> #{ipv4}/#{ipv6}")
                create_domain(domain, ipv4)
                dns_update_check({'domain' => domain, 'name' => '', 'type' => 'AAAA', 'data' => ipv6 })
                create_subdomains(['www'], domain, config, ['ipv4', 'ipv6-web'])
              else
                create_domain(domain, nil)
              end
              create_subdomains(subdomains, domain, config, typ_cfg)
            })
          }
        end
      }
    }
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
          if not settings['dns'][inv_type].nil?
            pub.write("[#{server}]\n")
            pub.write(settings['dns'][inv_type].first)
            pub.write(" server_name=#{server}")
            pub.write("\n\n")
          end
        }
      }
    }
  end

  def save_state()
    File.open(@state_file, 'w') { |f| YAML.dump(@state, f) }
  end

end
