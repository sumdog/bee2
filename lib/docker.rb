#!/usr/bin/env ruby

require 'docker'
require 'git'
require 'fileutils'
require 'tmpdir'

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
    else
      @log.error("Unknown command #{cmds[1]}")
      usage()
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
  def transform_envs(envs, cprefix)
    envs.map { |var,val|
      if var == 'domains' and val == 'all'
        # DOMAINS="bee2-app-name1:example.com,example.org bee2-app-name2:someotherdomain.com"
        full_map = all_domains.map { |app,domains|
          "#{@prefix}-#{cprefix}-#{app}:#{domains.join(',')}"
        }.join(' ')
        "#{var.upcase}=#{full_map}"
      elsif var == 'domains' and val.respond_to?('join')
        "#{var.upcase}=#{val.join(' ')}"
      elsif val.is_a?(String) and val.start_with?('$')
        ref_container = @config['applications'].select { |a,c| a == val.tr('$', '') }
        if ref_container.nil?
          @log.error("Could not find reference for #{val} in configuration.")
          exit 3
        else
          "#{@prefix}-#{cprefix}-#{ref_container.first[0]}"
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

      create_container("#{@prefix}-#{tcfg[:prefix]}-#{name}",
        cfg.fetch('image', nil),
        tcfg[:prefix],
        build_dir,
        cfg.fetch('git', nil),
        cfg.fetch('ports', nil),
        transform_envs(cfg.fetch('env', []), tcfg[:prefix]),
        cfg.fetch('link', nil),
        cfg.fetch('volumes', nil)
      )
    }.inject(&:merge)
  end

  def create_container(name, image, cprefix, build_dir, git, ports, env, link, volumes)
    {
     name => {
       'image' => image,
       'build_dir' => build_dir,
       'git' => git,
       'container_args' => {
         "RestartPolicy": { "Name": "unless-stopped" },
         'Env' => env,
         'ExposedPorts' => (ports.map { |port| {"#{port}/tcp" => {}}}.inject(:merge) if not ports.nil?),
         'HostConfig' => {
           'Links' => (link.map{ |l| "#{@prefix}-#{cprefix}-#{l}" } if not link.nil?),
           'Binds' => (volumes if not volumes.nil?),
           'PortBindings' => (ports.map { |port| {
             "#{port}/tcp" => [{ 'HostPort' => "#{port}" }]}
           }.inject(:merge) if not ports.nil?)
         }.reject{ |k,v| v.nil? }
       }.reject{ |k,v| v.nil? }
     }.reject{ |k,v| v.nil? }
   }
  end

  def launch_containers(containers, wait = false, post_complete = nil)
    containers.map { |name, params|
      # for all bee2 containers that don't exist yet
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
          params['image']
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
