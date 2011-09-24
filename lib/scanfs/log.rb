# -*- encoding: binary -*-

require 'logger'

module ScanFS::Log


  DEFAULT_LOG = ::Logger.new(STDOUT)
  DEFAULT_LOG_COUNT = 7
  DEFAULT_LOG_SIZE = 1024**3 # 1MB


  def log
    @@log ||= DEFAULT_LOG
  end

  def self.log
    @@log ||= DEFAULT_LOG
  end

  def self.device=(log_device)
    # quack quack
    [:debug, :info, :warn, :error, :fatal, :unknown, :level=].each { |method|
      unless log_device.respond_to?(method)
        warn "failed to set log device: did not respond to method :#{method}"
        return nil
      end
    }
    @@log = log_device
  end

  def self.configure(opts={})

    if opts[:logfile]
      begin
        @@log = ::Logger.new(
          opts[:logfile],
          DEFAULT_LOG_COUNT,
          DEFAULT_LOG_SIZE
        )
      rescue StandardError => e
        raise ScanFS::Error.new("failed to configure logfile: #{e}")
      end
    else
      @@log = DEFAULT_LOG
    end

    if opts[:debug]
      @@log.level = ::Logger::DEBUG
    elsif opts[:verbose]
      @@log.level = ::Logger::INFO
    elsif opts[:quiet]
      @@log.level = ::Logger::ERROR
    else
      @@log.level = ::Logger::WARN
    end

  end


end # module ScanFS::Log
