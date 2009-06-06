
require 'hmac'
require 'hmac-sha1'
require 'base64'

class Cryptic

  def self.hash(simplekey, url, auth_token, ticks)
    string = "http://bit.ly/3YmXa:" #funny guys :-)
    string += "#{simplekey}-#{auth_token}**#{ticks.to_s}"
    Base64.encode64(HMAC::SHA1.digest(string, url)).to_s.strip
  end
  
end