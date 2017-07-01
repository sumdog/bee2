#!/usr/bin/env ruby

require 'yaml'
require 'optparse'
require_relative 'lib/provisioners'


options = {}
opts = OptionParser.new do |opts|

  opts.banner = 'Usage: provision [-h|--help] [-c <config>] [-r]'

  opts.on_tail("-h", "--help", "Show this message") do
    STDERR.puts opts
    exit
  end

  opts.on('-c','--config CONFIG','Configuration File') do |config|
    options[:config] = config
  end

  opts.on('-r','--rebuild','Destory and Rebuild Servers') do |rebuild|
    options[:rebuild] = rebuild
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
p = VultrProvisioner.new(config)
p.provision(rebuild = options[:rebuild])
