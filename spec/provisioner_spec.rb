require 'tempfile'
require 'logger'
require_relative '../lib/provisioner'

class MockProvisioner < Provisioner

  attr_accessor :state, :domains_created, :update_check

  def initialize(cfg_yaml, log)
    super(cfg_yaml, log)
    @domains_created = {}
    @existing_domains = [ 'example.com' ]
    @update_check = []
  end

  def list_domain_records(domain, ok_func, err_func)
    if @existing_domains.include?(domain)
      ok_func.()
    else
      err_func.()
    end
    #{'name' => '', 'type' => 'A', 'data' => '1.1.1.1'}
  end

  def create_domain(domain, ip)
    @domains_created[domain] = ip
    @existing_domains.push(domain)
  end

  def dns_update_check(r)
    @update_check.push(r)
  end

end

RSpec.describe Provisioner do

  tmp_state = Tempfile.new('bee2_test_state')
  tmp_public_inv = Tempfile.new('bee2_test_public_inv')
  tmp_private_inv = Tempfile.new('bee2_test_private_inv')
  log = Logger.new(STDOUT)
  log.level = Logger::ERROR

  after(:all) do
    tmp_state.unlink
    tmp_public_inv.unlink
    tmp_private_inv.unlink
  end

  state = <<-STATE
  servers:
    srv1:
      ipv4:
        addr: 10.10.10.1
      ipv6:
        addr: fe80:aaaa:bbbb:cccc::61
        subnet: 'fe80:aaaa:bbbb:cccc::'
    srv6:
      ipv4:
        addr: 10.20.20.1
      ipv6:
        addr: fe80:aaaa:bbbb:dddd::62
        subnet: 'fe80:aaaa:bbbb:dddd::'
  STATE

  config = <<-CONFIG
  provisioner:
    state_file: #{tmp_state.path}
  inventory:
    public: #{tmp_public_inv.path}
    private: #{tmp_private_inv.path}
  servers:
    srv6:
      private_ip: 192.168.1.1
      ipv6:
        docker:
          suffix_bridge: 1:0:0/96
          suffix_net: 2:0:0/96
          static_web: 2:aaaa:a
      dns:
        public:
          - web.example.com
        private:
          - web.example.net
        web:
          - battlepenguin.com
          - penguindreams.org
          - social.battlepenguin.com
          - tech.battlepenguin.com
    srv1:
      dns:
        public:
          - srv1.example.com
  CONFIG

  cfg_yaml = YAML.load(config)
  pro = MockProvisioner.new(cfg_yaml, log)
  pro.state = YAML.load(state)

  describe "Domain Records" do
    it "convert examples in code comments/documentation" do
      expect(pro.domain_records([ 'something.example.com', 'some.other.example.com', 'example.net', 'somethingelse.example.net', 'example.org' ])).to(
        eq( { 'example.com' => [ 'something', 'some.other' ], 'example.net' => ['somethingelse'], 'example.org' => [] })
      )
    end
    it "convert domain array from YAML config to a hash from each base to subdomains" do
      expect(pro.domain_records(cfg_yaml['servers']['srv6']['dns']['web'])).to eq(
         {"battlepenguin.com"=>["social", "tech"], "penguindreams.org"=>[]}
      )
    end
  end

  describe "List Current Domain Records" do
    it "runs ok function if domain is found" do
      acc = false
      pro.list_domain_records('example.com', ->{ acc = true }, ->{ fail 'domain should exist in test fixture' })
      expect(acc).to eq(true)
    end
    it "runs error function if domain is not found" do
      acc = false
      pro.list_domain_records('example.net', ->{ fail 'domain should not exist in test fixture' }, ->{ acc = true })
      expect(acc).to eq(true)
    end
  end

  # TODO: fix mock
  # describe "Update DNS" do
  #   it "creates new domains" do
  #     pro.update_dns
  #     expect(pro.domains_created).to eq({"example.net"=>nil})
  #     pro.domains_created = {}
  #   end
  #   it "skip created domains" do
  #     pro.update_dns
  #     expect(pro.domains_created).to eq({})
  #     pro.domains_created = {}
  #   end
  # end

  # describe "DNS Update Check" do
  #   it "visits all records to update A/AAAA names" do
  #   end
  # end

  describe "Web IPv6" do
    it "should not have a static_web in state for srv6 prior to running web_ipv6 function" do
      expect(pro.state['servers']['srv6']['ipv6']['static_web']).to be_nil
    end
    it "should add an haproxy/docker container IPv6 Address for srv6" do
      pro.web_ipv6
      expect(pro.state['servers']['srv6']['ipv6']['static_web']).to eq('fe80:aaaa:bbbb:dddd::2:aaaa:a')
    end
    it "should not add an haproxy/docker container IPv6 for srv1" do
      pro.web_ipv6
      expect(pro.state['servers']['srv1']['static_web']).to be_nil
    end
  end

  describe "Save State" do
    it "should save the current state to the state file" do
      pro.save_state
      expect(YAML.load_file(tmp_state)).to eq(pro.state)
    end
  end

  # TODO
  # describe "Save Inventory" do
  #  it "should save the public inventory" do
  #  end
  #  it "should save the private inventory" do
  #  end
  # end

end
