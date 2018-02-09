#!/usr/bin/env ruby

class SyncHandler

  private def usage()
    doc =<<-USAGE
Usage: bee2 -c <config> -s SERVER

    help    -  This usage message
    all     -  Sync all servers
    <name>  -  Sync individual server

    Performs an rsync operation for the given server
    based on the settings in the sync section of the
    configuration file.
    USAGE

    print(doc)
    exit 1
  end

  def initialize(config, log, server)
    @log = log
    @config = config

    case server
    when 'all'
    when 'test'
    else
      cmds = rsync_cmds(server)
      if cmds.empty?
      else
        run_rsync_cmds(cmds)
      end
    end
  end

  def rsync_cmds(server)
    server_dns = @config.fetch('servers', {}).fetch(server, {}).fetch('dns', {}).fetch('private', {})
    @config['sync'].fetch(server, {}).fetch('push', {}).map { |p|
      (local,remote) = p.split(':')
      ['-av', '--delete', '-e', "\"ssh -i #{@config['provisioner']['ssh_key']['private']}\"",
       local, "root@#{server_dns.first}:#{remote}"]
    }
  end

  def run_rsync_cmds(cmds)
    cmds.each { |c|
      @log.info("Syncing #{c[-2]} to #{c[-1]}")
      system((['rsync'] + c).join(' '))
    }
  end

end
