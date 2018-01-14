require 'gpgme'
require 'securerandom'
require 'fileutils'

class PassStore

  def initialize(config)
    @password_store = config.fetch('security', {}).fetch('password_store', File.join(Dir.home, '.password-store', 'bee2'))
    @crypt = GPGME::Crypto.new
    @pgp_id = config['security']['pgp_id']
  end

  ## rescue GPGME::Error::DecryptFailed upstream for failed passwords
  def get_or_generate_password(folder, name)
    pfile = File.join(@password_store, folder, "#{name}.gpg")
    if File.file?(pfile)
      open(pfile, 'rb') do |f|
        return @crypt.decrypt(f.read()).read().strip()
      end
    else
      new_passowrd = SecureRandom.hex
      FileUtils.mkdir_p File.join(@password_store, folder)
      File.open(pfile, 'wb') do |out|
        @crypt.encrypt new_passowrd, :recipients=>@pgp_id, :output=>out
      end
      return new_passowrd
    end
  end

end
