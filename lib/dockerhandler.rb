#!/usr/bin/env ruby

require 'docker'
require 'git'
require 'fileutils'
require 'tmpdir'
require 'json'
require_relative 'passstore'
require_relative 'util'

module Docker::Util
  def self.remove_ignored_files!(directory, files)
    # Remove this function as it breaks compatiablity
    # with the docker CLI; discovered with Pixelfed
  end
end

class DockerHandler

  private def usage()
    doc =<<-USAGE
Usage: bee2 -c <config> -d COMMAND

    help  -  This usage message

    Building/Rebuilding All Applications:
       <server>:build[:appname]
       <server>:rebuild[:appname]

       Exmaples:
         web1:build
         web1:rebuild:nginx

    Running Jobs:
       <server>:run[:job]

    USAGE

    print(doc)
    exit 1
  end

  def initialize(config, log, command, passstore)
    @log = log
    @config = config
    @passstore = passstore

    cmds = command.split(':')
    @server = cmds[0]

    @prefix = @config.fetch('docker',{}).fetch(@server, {}).fetch('prefix','bee2')
    @network = "#{@prefix}-network"

    if @server == 'help'
      usage()
    end
    cert_path = "conf/docker/#{@server}"

    server_dns = @config.fetch('servers', {}).fetch(@server, {}).fetch('dns', {}).fetch('private', {})
    if server_dns.nil?
      @log.error("Unknown server #{@server}")
      exit 2
    end

    Docker.url = "https://#{server_dns[0]}:2376"
    Docker.options = {
      client_cert: File.join(cert_path, 'docker-client.crt'),
      client_key: File.join(cert_path, 'docker-client.pem'),
      ssl_ca_file: File.join(cert_path, 'ca.pem'),
      ssl_verify_peer: false,
      scheme: 'https',
      read_timeout: @config.fetch('docker',{}).fetch('read_timeout', 900)
    }


    if cmds[1] != 'test'
      establish_default_network
      establish_other_networks
    end

    case cmds[1]
    when 'build'
      launch_containers(config_to_containers('apps', cmds[2]))
    when 'rebuild'
      clean_containers(cmds[2])
      launch_containers(config_to_containers('apps', cmds[2]))
    when 'run'
      clean_containers(cmds[2], 'job')
      launch_containers(config_to_containers('jobs', cmds[2]), true)
    when 'test'
    else
      @log.error("Unknown command #{cmds[1]}")
      usage()
    end
  end

  def state
    if(@config['provisioner'].has_key?('state_file'))
      YAML.load_file(@config['provisioner']['state_file'])
    else
      {}
    end
  end

  def establish_other_networks
    config_for_networks.each { |name, docker_cfg|
      net_name = "#{@prefix}-#{name}"
      if Docker::Network.all.select { |n| n.info['Name'] == net_name }.empty?
        # Logging only variables
        pub_ip4 = docker_cfg.fetch('Options', {}).fetch('com.docker.network.bridge.host_binding_ipv4', nil)
        p_msg = pub_ip4.nil? ? 'private' : "public_ip: #{pub_ip4}"
        msq = docker_cfg.fetch('Options', {}).fetch('com.docker.network.bridge.enable_ip_masquerade', false)
        m_msg = msq.nil? ? '' : '(masquerade disabled)'
        subnets = docker_cfg.fetch('IPAM', {}).fetch('Config', {}).map{ |n| n['Subnet']}.join(',')
        @log.info("Creating network #{net_name} subnets: #{subnets} #{docker_cfg['ipv6']} #{p_msg} #{m_msg}")
        require 'excon'
        begin
          Docker::Network.create(net_name, docker_cfg)
        rescue Excon::Error::Forbidden => e
          @log.error(e.response)
          raise e
        end
      end
    }
  end

  def config_for_networks
    @config.fetch('docker',{}).fetch(@server, {}).fetch('networks',{}).map { |name, cfg|
      [name,
        { "EnableIPv6" => cfg.has_key?('ipv6'),
          "IPAM" => {"Config" => [
            {"Subnet" => cfg['ipv6']},
            {"Subnet" => cfg['ipv4']}
          ].reject{|s| s['Subnet'].nil?}},
          "Options" => {
            "com.docker.network.bridge.host_binding_ipv4" =>
                @config.fetch('servers', {}).fetch(@server, {})
                    .fetch('ip',{}).fetch(name, {}).fetch('ipv4', nil),
            "com.docker.network.bridge.enable_ip_masquerade" => cfg['masquerade'] == false ? "false" : nil,
            "com.docker.network.bridge.name" => cfg.fetch('bridge', nil),
            "com.docker.network.container_interface_prefix" => cfg.fetch('ifprefix', nil)
          }.reject{ |k,v| v.nil? }
        }
      ]
    }.to_h
  end

  def establish_default_network
    if not state.fetch('servers', {}).fetch(@server, {}).fetch('ipv6', {}).empty?
      ipv6_subet = state['servers'][@server]['ipv6']['subnet']
      ipv6_suffix = @config['servers'][@server]['ipv6']['docker']['suffix_net']
      ipv6 = "#{ipv6_subet}#{ipv6_suffix}"

      if Docker::Network.all.select { |n| n.info['Name'] == @network }.empty?
        @log.info("Creating network #{@network} with IPv6 Subnet #{ipv6}")
        Docker::Network.create(@network, {"EnableIPv6" => true,
          "IPAM" => {"Config" => [
            {"Subnet" => ipv6}
          ]}
        })
      end
    else
      if Docker::Network.all.select { |n| n.info['Name'] == @network }.empty?
        @log.info("Creating network #{@network} without IPv6")
        Docker::Network.create(@network, {"EnableIPv6" => false})
      end
    end
  end

  # Returns hash mapping applications to domains
  # excluding nils and the specail case 'all'
  def all_domains
    docker_cfg['applications'].select { |app, cfg|
      cfg.has_key?('env') }.map { |app,l|
        { app => l['env']}
      }.inject(:merge).map { |app, env|
        { app => env['domains'] }
      }.inject(:merge).reject { |a,r|
        r =='all' or r.nil?
      }
  end

  # Returns {"mysql" => "***", "postgres" => "***", "redis => "***"}
  def db_admin_passwords
    Hash[ db_mapping.uniq { |i| i[:db] }.map { |j| j[:db] }.collect { |db|
      [db, @passstore.get_or_generate_password("database/#{db}", 'admin') ]
    }]
  end

  # Returns [ {:container => "name", :password => "***", :db=>"mysql"} ]
  def db_mapping
    # Identify all containers that request a database (link: _dbtype)
    db_map = ['applications', 'jobs'].map { |section|
      docker_cfg[section].select { |app, cfg|
        cfg.has_key?('db') }.map { |app, l|
          l['db'].map { |db|
            db_parts = db.split(':')
            db_name = db_parts[1].nil? ? app : db_parts[1]
            { :container => db_name, :db => db_parts[0] }
          }
        }
    }.flatten

    # Ensure passwords for all of them
    db_map.map { |m|
      m.merge({:password => @passstore.get_or_generate_password("database/#{m[:db]}", m[:container])})
    }
  end

  def existing_containers
    enum_for(:bee2_containers).to_a
  end

  def bee2_containers
    Docker::Container.all(:all => true).each { |c|
      c.info['Names'].each { |name|
        if(name.start_with?("/#{@prefix}"))
          unit = name.split('-')[1]
          if(unit)
            yield c
          end
        end
      }
    }
  end

  def docker_cfg
    @config['docker'][@server]
  end

  # used to determine if we should pull a specific database:
  #   _mysql:somedatabase^password
  #   _mysql^password  <-- uses container name
  private def container_password_select(c, db_type, name)
    if db_type.include?(':')
      parts = db_type.split(':')
      db_type = parts[0]
      db_name = parts[1]
    else
      db_name = name
    end
    return (c[:container] == db_name and c[:db] == db_type)
  end

  # Convert envs in YAML to environment variable strings
  # to be passed in to Docker
  # Handles the spcial case DOMAINS=all, expanding it to
  # a space seperated list of domains
  def transform_envs(name, envs, cprefix)
    envs.map { |var,val|
      if var == 'domains' and val == 'all'
        # DOMAINS="bee2-app-name1:example.com,example.org bee2-app-name2:someotherdomain.com/80"
        full_map = all_domains.map { |app,domains|
          "#{@prefix}-app-#{app}:#{domains.join(',')}"
        }.join(' ')
        "#{var.upcase}=#{full_map}"
      elsif var == 'domains' and val.respond_to?('join')
        "#{var.upcase}=#{val.join(' ')}"
      elsif val.is_a?(String) and val.start_with?('_')
        # Database vars
        (db_type, db_var) = Util.lstrip_underscore(val).split('^')
        case db_type
        when 'dbmap'
          db_info = {:admin => db_admin_passwords, :containers => db_mapping}
          "#{var.upcase}=#{JSON.dump(db_info)}"
        else
          case db_var
          when 'password'
            db_pass = db_mapping.select { |c|
              container_password_select(c, db_type, name)
            }.first[:password]
            "#{var.upcase}=#{db_pass}"
          when 'adminpass'
            "#{var.upcase}=#{db_admin_passwords[db_type]}"
          else
            @log.error("Unknown variable #{db_var} for #{db_type}")
            exit 3
          end
        end
      elsif val.is_a?(String) and val.start_with?('$')
        ref_container = docker_cfg['applications'].select { |a,c| a == val.tr('$', '') }
        if ref_container.nil?
          @log.error("Could not find reference for #{val} in app configuration.")
          exit 3
        else
          "#{var.upcase}=#{@prefix}-app-#{ref_container.first[0]}"
        end
      elsif val.is_a?(String) and val.start_with?('+')
        ref_container = docker_cfg['jobs'].select { |a,c| a == val.tr('+', '') }
        if ref_container.nil?
          @log.error("Could not find reference for #{val} in job configuration.")
          exit 3
        else
          "#{var.upcase}=#{@prefix}-job-#{ref_container.first[0]}"
        end
      else
        "#{var.upcase}=#{val}"
      end
    }.flatten
  end

  def clean_containers(name, ctype = 'app')

    containers = if not name.nil?
      existing_containers.select { |c| c.info['Names'].any? { |n| n == "/#{@prefix}-#{ctype}-#{name}" } }
    else
      existing_containers
    end

    containers.each { |c|
      begin
        @log.info('Deleting Container %s' %[c.info['Names']])
        c.delete(:force => true)
      rescue Docker::Error::NotFoundError
        @log.warn('Could not delete container. Container not found.')
      end
    }
  end

  def config_to_containers(ctype, container)
    tcfg = case ctype
    when 'apps' then {:section => 'applications', :prefix => 'app'}
    when 'jobs' then {:section => 'jobs', :prefix => 'job'}
    end

    containers = {}
    if not container.nil?
      c = docker_cfg[tcfg[:section]][container]
      if c.nil?
        @log.error("Could not find docker/#{@server}/#{tcfg[:section]}/#{container}")
        exit 3
      else
        containers = { container => c }
      end
    else
      containers = docker_cfg[tcfg[:section]]
    end

    containers.map { |name, cfg|

      build_dir = cfg.fetch('build_dir', nil)
      if not build_dir.nil?
        build_dir = File.join('./dockerfiles', build_dir)
      end

      # Web static IPv6
      static_ipv6 = nil
      if cfg.fetch('ipv6_web', false)
        ipv6_subet = state['servers'][@server]['ipv6']['subnet']
        ipv6_web = @config['servers'][@server]['ipv6']['docker']['static_web']
        static_ipv6 = "#{ipv6_subet}#{ipv6_web}"
      end

      # Multiple Defined Networks
      networks = [@network]
      if cfg.has_key?('networks')
        networks = cfg['networks'].map { |n| "#{@prefix}-#{n}" }
      end

      # If there are multiple networks defined for a container
      # the first one is used for the IPv6 address
      ipv6addr = @config.fetch('servers', {}).
                         fetch(@server, {}).
                         fetch('ip', {}).
                         fetch(cfg.fetch('networks', []).first, {}).
                         fetch('ipv6', nil)

      create_container("#{@prefix}-#{tcfg[:prefix]}-#{name}",
        cfg.fetch('image', nil),
        tcfg[:prefix],
        cfg.fetch('cmd', nil),
        networks,
        build_dir,
        cfg.fetch('git', nil),
        cfg.fetch('branch', nil),
        cfg.fetch('git_dir', nil),
        cfg.fetch('dockerfile', nil),
        cfg.fetch('ports', nil),
        transform_envs(name, cfg.fetch('env', []), tcfg[:prefix]),
        cfg.fetch('labels', nil),
        cfg.fetch('volumes', nil),
        cfg.fetch('ipv4', nil),
        # ipv6 addr is for the public network IPv6 NAT
        # static_ipv6 is for assinging a pulic IPv6 address to a container without IPv6 NAT
        ipv6addr,
        static_ipv6
      )
    }.inject(&:merge)
  end

  def create_container(name, image, cprefix, cmd, networks, build_dir, git, branch, git_dir, dockerfile, ports, env, labels, volumes, ipv4, ipv6, static_ipv6 = nil)
    {
     name => {
       'image' => image,
       'build_dir' => build_dir,
       'git' => git,
       'branch' => branch,
       'git_dir' => git_dir,
       'dockerfile' => dockerfile,
       'additional_networks' => networks[1..-1],
       'container_args' => {
         'Env' => env,
         'Labels' => labels,
         'Cmd' => (cmd.split(' ') if not cmd.nil?),
         'NetworkingConfig' =>
           {'EndpointsConfig' =>
             {networks.first =>
               {
                 'IPAMConfig' => {'IPv6Address' => static_ipv6 }.reject{ |k,v| v.nil? }
               }
             }
           },
         'ExposedPorts' => (ports.map { |port| {"#{port}/tcp" => {}}}.inject(:merge) if not ports.nil?),
         'HostConfig' => {
           'RestartPolicy' => { 'Name' => (cprefix == 'app' ? 'unless-stopped' : 'no') },
           'Binds' => (volumes if not volumes.nil?),
           'PortBindings' => (ports.map { |port|
             {
               "#{port}/tcp" => [
                 # TODO: this will break with certain ipv4/v6 combinations that are outside of my use cases
                 # see docker_spec.rb
                 { 'HostPort' => "#{port}", 'HostIp' => ipv4 }.reject{ |k,v| v.nil? },
                 { 'HostPort' => "#{port}", 'HostIp' => ipv6 }
               ].reject{ |v| v.has_key?('HostIp') and v['HostIp'].nil? }
             }.reject{ |k,v| v.nil? }
           }.inject(:merge) if not ports.nil?)
         }.reject{ |k,v| v.nil? }
       }.reject{ |k,v| v.nil? }
     }.reject{ |k,v| v.nil? }
   }
  end

  def launch_containers(containers, wait = false, post_complete = nil)
    containers.map { |name, params|

      # for all bee2 app containers that don't exist yet
      if not existing_containers.any? { |e| e.info['Names'].any? { |n| n == "/#{name}" } }
        image = case
        when params.key?('build_dir')
          @log.info('Creating Image for %s' %[name])
          Docker::Image.build_from_dir(params['build_dir']).id
        when params.key?('git')
          Dir.mktmpdir {|git_dir|
            @log.info("Git Clone #{params['git']}")
            git = Git.clone(params['git'], '.', :path => git_dir)
            if params.key?('branch')
              @log.info("Using branch #{params['branch']}")
              #git.branches[params['branch']].checkout()
              # Allows checkout of a branch or tag
              git.checkout(params['branch'])
            end
            docker_dir = nil
            docker_params = {}
            if params.key?('git_dir')
              @log.info("Creating Image for #{params['git']}/#{params['git_dir']}")
              docker_dir = File.join(git_dir, params['git_dir'])
            else
              @log.info("Creating Image for #{params['git']}")
              docker_dir = git_dir
            end
            if params.key?('dockerfile')
              @log.info("Using custom dockerfile: #{params['dockerfile']}")
              docker_params['dockerfile'] = params['dockerfile']
            end
            Docker::Image.build_from_dir(docker_dir, docker_params).id
          }
        when params.key?('image')
          @log.info("Pulling Image #{params['image']}")
          Docker::Image.create('fromImage' => params['image']).id
        else
          @log.error('Missing image key')
        end
        @log.debug('Image Id %s' %[image])

        c = Docker::Container.create(
          {
            'Image' => image,
            'name' => "#{name}"
          }.merge(params['container_args'])
        )

        if params['additional_networks']
          params['additional_networks'].each { |net|
            @log.info("Adding additional network #{net}")
            docker_network = Docker::Network.all.select { |n| n.info['Name'] == net }.first
            docker_network.connect(c.id)
          }
        end

        c.start()
        @log.info("#{name} container started")

        if wait
          @log.info("Waiting for #{name} to complete")
          status = c.wait()
          if status['StatusCode'] != 0
            @log.error("Container #{name} exited with #{status['StatusCode']}")
            abort('Container exited with abnormal status code')
          else
            @log.info("#{name} finished")
          end

          if not post_complete.nil?
            @log.info("Running post complete hook for #{name}")
            post_complete.(c)
          end

        end
      else
        @log.info("Container #{name} already exists")
      end
    }
  end

end
