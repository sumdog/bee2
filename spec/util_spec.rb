require_relative '../lib/util'

RSpec.describe Util do

  describe "Strip Underscores" do
    it "strips leading underscores" do
      expect(Util.lstrip_underscore("_foo")).to eq("foo")
    end
    it "does not strip trailing underscores" do
      expect(Util.lstrip_underscore("foo_")).to eq("foo_")
    end
    it "does not strip non-leading underscores" do
      expect(Util.lstrip_underscore("_foo_bar")).to eq("foo_bar")
    end
    it "leaves strings with no underscores unaltered" do
      expect(Util.lstrip_underscore("bar")).to eq("bar")
    end
  end

  describe "Base domain" do
    it "removes leading subdomain" do
      expect(Util.base_domain("test.example.com")).to eq("example.com")
    end
    it "removes leading subdomains" do
      expect(Util.base_domain("a.b.c.d.test.example.com")).to eq("example.com")
    end
    it "removes leading subdomain with secondary base" do
      expect(Util.base_domain("test.example.co.uk")).to eq("example.co.uk")
    end
    it "removes leading subdomains with secondary base" do
      expect(Util.base_domain("a.b.c.d.test.example.co.uk")).to eq("example.co.uk")
    end
  end

  describe "Host subdomain" do
    it "single leading subdomain" do
      expect(Util.host_domain("test.example.com")).to eq("test")
    end
    it "multiple leading subdomains" do
      expect(Util.host_domain("a.b.c.d.test.example.com")).to eq("a.b.c.d.test")
    end
    it "single leading subdomain with secondary base" do
      expect(Util.host_domain("test.example.co.uk")).to eq("test")
    end
    it "multiple leading subdomains with secondary base" do
      expect(Util.host_domain("a.b.c.d.test.example.co.uk")).to eq("a.b.c.d.test")
    end
  end

  describe "WWW subdomain" do
    it "web subdomain for io url" do
      expect(Util.host_domain("www.wiki-dev.bigsense.io")).to eq("www.wiki-dev")
    end
    it "base for web subdomain for io url" do
      expect(Util.base_domain("www.wiki-dev.bigsense.io")).to eq("bigsense.io")
    end
  end

  describe "Primary Domain" do
    it "should have an empty host" do
      expect(Util.host_domain("bigsense.io")).to eq("")
    end
    it "should have a full base" do
      expect(Util.base_domain("bigsense.io")).to eq("bigsense.io")
    end
  end

end
