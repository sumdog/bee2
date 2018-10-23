class Provisioner

  def initialize(config, log)
    @log = log

    if(config['provisioner'].has_key?('state_file)'))
      @state_file = config['provisioner']['state_file']
      if File.exists? @state_file
        @state = YAML.load_file(@state_file)
      else
        @state = {}
      end
    end

  end

  def save_state()
    File.open(@state_file, 'w') { |f| YAML.dump(@state, f) }
  end

end
