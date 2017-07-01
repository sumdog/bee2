#!/usr/bin/env ruby

require 'yaml'
require 'optparse'
require 'logger'
require_relative 'lib/vultr'


options = {}
opts = OptionParser.new do |opts|

  opts.banner = 'Usage: provision [-h|--help] [-c <config>] [-p [-r]]'

  opts.on('-c','--config CONFIG','Configuration File') do |config|
    options[:config] = config
  end

  opts.on('-p', '--provision', 'Provision Servers') do |provision|
    options[:provision] = provision
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

log = Logger.new(STDOUT)

config = YAML.load_file(options[:config])
case config['provisioner']['type']
when 'vultr'
  p = VultrProvisioner.new(config)
when 'digitalocean'
  @log.warn('Not Implemented')
end

if options[:provision]
  p.provision(rebuild = options[:rebuild])
end

if options[:inventory]
  inv_file = config['inventory'][options[:inventory]]
  log.info("TODO: Ansible #{options[:inventory]} #{inv_file}")
end
