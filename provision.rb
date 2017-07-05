#!/usr/bin/env ruby

require 'yaml'
require 'optparse'
require 'logger'
require_relative 'lib/vultr'

log = Logger.new(STDOUT)

options = {}
opts = OptionParser.new do |opts|

  opts.banner = 'Usage: provision [-v] [-h|--help] [-c <config>] [-p [-r]]'

  opts.on('-c','--config CONFIG','Configuration File') do |config|
    options[:config] = config
  end

  opts.on('-p', '--provision', 'Provision Servers') do |provision|
    options[:provision] = provision
  end

  opts.on('-v', '--verbose', 'Debug Logging Ouput Enabled') do |verbose|
    if options[:verbose]
      log.level = Logger::DEBUG
    else
      log.level = Logger::INFO
    end
  end

  opts.on('-r','--rebuild','Destory and Rebuild Servers During Provisioning') do |rebuild|
    options[:rebuild] = rebuild
  end

  opts.on('-a', '--ansible INVENTORY', [:public, :private], 'Run Ansible on Inventory (public|private)') do |ansible|
    options[:inventory] = ansible
  end

  opts.on_tail("-h", "--help", "Show this message") do
    STDERR.puts opts
    exit
  end
end

begin opts.parse! ARGV
rescue *[OptionParser::InvalidOption,OptionParser::InvalidArgument,OptionParser::MissingArgument] => e
  STDERR.puts e
  STDERR.puts opts
  exit 1
end

config = YAML.load_file(options[:config])
case config['provisioner']['type']
when 'vultr'
  p = VultrProvisioner.new(config, log)
when 'digitalocean'
  @log.warn('Not Implemented')
end

if options[:provision]
  p.provision(rebuild = options[:rebuild])
end

if options[:inventory]
  inv_file = config['inventory'][options[:inventory].to_s]
  # Get a hash of server to roles: {'server' => ['role1', 'role2']}
  # Thanks: al2o3-cr (#ruby/freenode)
  playbooks = config['servers'].flat_map { |server, info| {server => info['playbook']} }.inject(:update)
  log.info("Running Ansible (Inventory: #{options[:inventory]} :: #{inv_file})")
  playbooks.each { |server, playbook|
    log.info("Applying #{playbook} to #{server}")
    cmd = ['ansible-playbook', '-C', '--limit', server, '--key-file', config['provisioner']['ssh_key']['private'],
           '-u', 'root', '-e', "config_file=#{options[:config].to_s}", '-i', inv_file, "ansible/#{playbook}"]
    log.debug(cmd)
    Process.fork do
      exec(*cmd)
    end
    Process.wait
  }
end
