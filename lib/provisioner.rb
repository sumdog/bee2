class Provisioner

  def initialize(config, log)
    @log = log

    @state_file = config['provisioner']['state_file']
    if File.exists? @state_file
      @state = YAML.load_file(@state_file)
    else
      @state = {}
    end

  end

  def save_state()
    File.open(@state_file, 'w') { |f| YAML.dump(@state, f) }
  end

end
