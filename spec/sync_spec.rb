require 'yaml'
require_relative '../lib/synchandler'
require 'logger'

log = Logger.new(STDOUT)

RSpec.describe SyncHandler do
  prefix = 'foo2'
  config = <<-CONFIG
  provisioner:
    ssh_key:
      private: conf/my-key
  servers:
    web1:
      dns:
        private:
          - web1.private
    web2:
      dns:
        private:
          - web2.private
  sync:
    web1:
      push:
        - /media/local1/photos:/media/remote1/photos
    web2:
      push:
        - /media/local2/data:/media/remote2/data
        - /media/local2/pool:/media/remote2/swimming
  CONFIG

  describe "rsync command generation" do
    it "empty list when given a non-existant server" do
      r = SyncHandler.new(YAML.load(config), log, 'test')
      expect(r.rsync_cmds('x1')).to be_empty
    end

    it "generates a set of parameters for web1" do
      r = SyncHandler.new(YAML.load(config), log, 'test')
      r = r.rsync_cmds('web1')
      expect(r.length).to eq(1)
      expect(r.first).to contain_exactly(
        '-av', '--delete', '-e', '"ssh -i conf/my-key"',
        '/media/local1/photos',
        'root@web1.private:/media/remote1/photos')
    end

    it "generates a set of parameters for web2" do
      r = SyncHandler.new(YAML.load(config), log, 'test')
      r = r.rsync_cmds('web2')
      expect(r.length).to eq(2)
      expect(r.first).to contain_exactly(
        '-av', '--delete', '-e', '"ssh -i conf/my-key"',
        '/media/local2/data',
        'root@web2.private:/media/remote2/data')
      expect(r.last).to contain_exactly(
        '-av', '--delete', '-e', '"ssh -i conf/my-key"',
        '/media/local2/pool',
        'root@web2.private:/media/remote2/swimming')
    end
  end

end
