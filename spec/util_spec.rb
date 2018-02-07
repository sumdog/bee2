require_relative '../lib/util'

RSpec.describe Util do

  describe "Utilities" do
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

end
