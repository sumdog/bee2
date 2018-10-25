require 'public_suffix'

class Util

  def self.lstrip_underscore(s)
    s.sub(/^[_:]*/,"")
  end

  def self.base_domain(domain)
    PublicSuffix.domain(domain)
  end

  def self.host_domain(domain)
    if Util.base_domain(domain) == domain
      ""
    else
      domain.chomp(".#{Util.base_domain(domain)}")
    end
  end

end
