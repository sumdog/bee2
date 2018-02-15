#!/usr/bin/env ruby

require 'docker'
require 'git'
require 'fileutils'
require 'tmpdir'
require 'json'
require_relative 'passstore'
require_relative 'util'

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

    Volumes:
      <server>:backup
      <server>:restore[:timestamp]

      Examples:
        web1:backup
        web1:restore
        web1:restore:1510205477
    USAGE

    print(doc)
    exit 1
  end

  def initialize(config, log, command)
    @log = log
    @config = config
    @prefix = @config.fetch('docker',{}).fetch('prefix','bee2')
    @passstore = PassStore.new(@config)
    @network = "#{@prefix}-network"

    cmds = command.split(':')
    server = cmds[0]

    if server == 'help'
      usage()
    end

    @volumes = @config.fetch('docker', {}).fetch('backup', {}).fetch(server, {}).fetch('volumes', []).map { |vol|
      "#{vol}:/volumes/#{vol}"
    }
    @backup_dir = @config.fetch('docker', {}).fetch('backup', {}).fetch(server, {}).fetch('storage_dir', './volumes')

    cert_path = "conf/docker/#{server}"

    server_dns = @config.fetch('servers', {}).fetch(server, {}).fetch('dns', {}).fetch('private', {})
    if server_dns.nil?
      @log.error("Unknown server #{server}")
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
      establish_network(server)
    end

    case cmds[1]
    when 'build'
      launch_containers(config_to_containers('apps', server, cmds[2]))
    when 'rebuild'
      clean_containers(cmds[2])
      launch_containers(config_to_containers('apps', server, cmds[2]))
    when 'run'
      launch_containers(config_to_containers('jobs', server, cmds[2]), true)
    when 'backup'
      backup_volumes(server)
    when 'restore'
      restore_volumes(server, cmds[2])
    when 'test'
    else
      @log.error("Unknown command #{cmds[1]}")
      usage()
    end
  end

  def state
    YAML.load_file(@config['provisioner']['state_file'])
  end

  def establish_network(server)
    ipv6_subet = state['servers'][server]['ipv6']['subnet']
    ipv6_suffix = @config['servers'][server]['ipv6']['docker']['suffix_net']
    ipv6 = "#{ipv6_subet}#{ipv6_suffix}"

    if Docker::Network.all.select { |n| n.info['Name'] == @network }.empty?
      @log.info("Creating network #{@network} with IPv6 Subnet #{ipv6}")
      Docker::Network.create(@network, {"EnableIPv6" => true,
        "IPAM" => {"Config" => [
          {"Subnet" => ipv6}
        ]}
      })
    end
  end

  def backup_volumes(server)
    @log.info("Backing up volumes #{server}/#{@volumes}")
    FileUtils.mkdir_p(File.join(@backup_dir, server))
    backup_container = create_container(
      "#{@prefix}-volume-backup", nil, 'app', './dockerfiles/VolumeReader', nil, nil,
      nil, nil, @volumes
    )
    backup_name = File.join(@backup_dir, server, "#{Time.now.to_i}-volumes.tar")
    launch_containers(backup_container, true, -> c {
      @log.info("Creating #{backup_name}")
      File.open(backup_name, 'wb') do |tar|
        c.copy('/volumes') { |chunk| tar.write(chunk) }
      end
    })
  end

  def restore_volumes(server, date)
    vol_file = case date
    when nil # Get latest
      Dir.glob(File.join(@backup_dir, server, '*.tar')).sort.first
    else
      File.join(@backup_dir, server, "#{date}-volumes.tar")
    end

    @log.info("Restoring volume #{vol_file}")

    if vol_file.nil? or not File.exists?(vol_file)
      @log.error("Cannot find volume #{vol_file}")
      abort("Error restoring volume")
    end

    Dir.mktmpdir do |temp_dir|
      @log.debug "Temp dir: #{temp_dir}"
      FileUtils.cp_r 'dockerfiles/VolumeWriter/.', temp_dir
      FileUtils.cp(vol_file, File.join(temp_dir, 'restore.tar'))
      restore_container = create_container(
        "#{@prefix}-volume-restore", nil, 'app', temp_dir, nil, nil,
        nil, nil, @volumes
      )
      @log.info("Restoring volumes #{date}")
      launch_containers(restore_container, true)
    end
  end

  # Returns hash mapping applications to domains
  # excluding nils and the specail case 'all'
  def all_domains
    @config['applications'].select { |app, cfg|
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
      @config[section].select { |app, cfg|
        cfg.has_key?('db') }.map { |app, l|
          l['db'].map { |db|
            { :container => app, :db => db }
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

  # Convert envs in YAML to environment variable strings
  # to be passed in to Docker
  # Handles the spcial case DOMAINS=all, expanding it to
  # a space seperated list of domains
  def transform_envs(name, envs, cprefix)
    envs.map { |var,val|
      if var == 'domains' and val == 'all'
        # DOMAINS="bee2-app-name1:example.com,example.org bee2-app-name2:someotherdomain.com"
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
              c[:container] == name and c[:db] == db_type
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
        ref_container = @config['applications'].select { |a,c| a == val.tr('$', '') }
        if ref_container.nil?
          @log.error("Could not find reference for #{val} in configuration.")
          exit 3
        else
          "#{var.upcase}=#{@prefix}-app-#{ref_container.first[0]}"
        end
      else
        "#{var.upcase}=#{val}"
      end
    }.flatten
  end

  def clean_containers(name)

    containers = if not name.nil?
      existing_containers.select { |c| c.info['Names'].any? { |n| n == "/#{@prefix}-app-#{name}" } }
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

  def config_to_containers(ctype, server, container)
    tcfg = case ctype
    when 'apps' then {:section => 'applications', :prefix => 'app'}
    when 'jobs' then {:section => 'jobs', :prefix => 'job'}
    end

    containers = {}
    if not container.nil?
      c = @config[tcfg[:section]][container]
      if c.nil?
        @log.error("Could not find #{tcfg[:section]}/#{container}")
        exit 3
      else
        containers = { container => c }
      end
    else
      containers = @config[tcfg[:section]]
    end

    containers.select { |n, c|
      c['server'] == server }.map { |name, cfg|

      build_dir = cfg.fetch('build_dir', nil)
      if not build_dir.nil?
        build_dir = File.join('./dockerfiles', build_dir)
      end

      # Web static IPv6
      static_ipv6 = nil
      if cfg.fetch('ipv6_web', false)
        ipv6_subet = state['servers'][server]['ipv6']['subnet']
        ipv6_web = @config['servers'][server]['ipv6']['docker']['static_web']
        static_ipv6 = "#{ipv6_subet}#{ipv6_web}"
      end

      create_container("#{@prefix}-#{tcfg[:prefix]}-#{name}",
        cfg.fetch('image', nil),
        tcfg[:prefix],
        build_dir,
        cfg.fetch('git', nil),
        cfg.fetch('ports', nil),
        transform_envs(name, cfg.fetch('env', []), tcfg[:prefix]),
        cfg.fetch('volumes', nil),
        static_ipv6
      )
    }.inject(&:merge)
  end

  def create_container(name, image, cprefix, build_dir, git, ports, env, volumes, static_ipv6 = nil)
    {
     name => {
       'image' => image,
       'build_dir' => build_dir,
       'git' => git,
       'container_args' => {
         "RestartPolicy": { "Name": "unless-stopped" },
         'Env' => env,
         'NetworkingConfig' =>
           {'EndpointsConfig' =>
             {@network =>
               {
                 'IPAMConfig' => {'IPv6Address' => static_ipv6 }.reject{ |k,v| v.nil? }
               }
             }
           },
         'ExposedPorts' => (ports.map { |port| {"#{port}/tcp" => {}}}.inject(:merge) if not ports.nil?),
         'HostConfig' => {
           'Binds' => (volumes if not volumes.nil?),
           'PortBindings' => (ports.map { |port| {
             "#{port}/tcp" => [
               { 'HostPort' => "#{port}" }
             ]}
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
            Git.clone(params['git'], '.', :path => git_dir)
            @log.info("Creating Image for #{params['git']}")
            Docker::Image.build_from_dir(git_dir).id
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

          c.delete(:force => true)
        end
      else
        @log.info("Container #{name} already exists")
      end
    }
  end

end
