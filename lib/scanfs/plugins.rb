# -*- encoding: binary -*-

require 'timeout'
require 'fileutils'

module ScanFS::Plugins


  PLUGIN_DIR_TIMEOUT = 3 # seconds
  USER_PLUGIN_DIR = File.join(ScanFS::Constants::USER_DIR, 'plugins')
  @@registry = {}


  def self.register(plugin)
    # plugin here is a Class
    if @@registry.include?("#{plugin.name}")
      ScanFS::Log.log.warn { "ignoring duplicate plugin: #{plugin.name}" }
    else
      @@registry["#{plugin.name}"] = plugin
      ScanFS::Log.log.info { "registered plugin: #{plugin.name}" }
    end
  end


  def self.registered?(plugin_name)
    @@registry.include?(plugin_name)
  end


  def self.known
    @@registry.keys
  end


  def self.info(plugin_name)
    if ScanFS::Plugins.registered?(plugin_name)
      {
      :author => @@registry[plugin_name].author,
      :version => @@registry[plugin_name].version,
      :description => @@registry[plugin_name].description
      }
    end
  end


  def self.make_user_plugin_dir
    Timeout.timeout(PLUGIN_DIR_TIMEOUT) { FileUtils.mkdir_p(USER_PLUGIN_DIR) }
    true
  rescue SystemCallError => e
    ScanFS::Log.log.debug { "failed to make user plugin dir: #{e.message}" }
    false
  rescue Timeout::Error
    ScanFS::Log.log.debug {
      "timed out making user plugin dir: #{USER_PLUGIN_DIR}"
    }
    false
  end


  def self.load_all(plugin_dir=nil)

    return false if plugin_dir.nil?

    unless File.exists?(plugin_abspath = File.expand_path(plugin_dir))
      if USER_PLUGIN_DIR == plugin_abspath
        return false unless ScanFS::Plugins.make_user_plugin_dir
      else
        ScanFS::Log.log.warn {
          "specified plugin dir does not exist: #{plugin_dir}"
        }
        return false
      end
    end

    unless File.readable?(plugin_abspath)
      ScanFS::Log.log.warn { "plugin dir not readable: #{plugin_dir}" }
      return false
    end

    ScanFS::Log.log.info { "loading plugins from: #{plugin_abspath}" }

    all_plugins_loaded = true
    begin
      Timeout.timeout(PLUGIN_DIR_TIMEOUT) {
        Dir.glob(File.join(plugin_abspath, '*.rb')) { |f|
          begin
            require f
          rescue LoadError, SyntaxError => e
            all_plugins_loaded = false
            ScanFS::Log.log.warn { "failed to load plugin #{f}: #{e.message}" }
            ScanFS::Log.log.debug { "#{e.backtrace.join("\n")}" }
          end
        }
      }
    rescue Timeout::Error
      ScanFS::Log.log.warn { "timed out reading plugin dir: #{plugin_abspath}" }
      all_plugins_loaded = false
    end

    all_plugins_loaded
  end


  def self.run(plugin_name, result, opts={})
    if ScanFS::Plugins.registered?(plugin_name)
      begin
        ScanFS::Log.log.debug { "running plugin: #{plugin_name}" }
        start_time = Time.now.to_f
        instance = @@registry[plugin_name].new(result, opts)
        instance.run
        elapsed = Time.now.to_f - start_time
        ScanFS::Log.log.debug {
          "plugin #{plugin_name} ran in #{elapsed} seconds"
        }
      rescue StandardError => e
        ScanFS::Log.log.error {
          "failed to run plugin #{plugin_name}: #{e.message}"+
          "\n#{e.backtrace.join("\n")}"
        }
      end
    else
      ScanFS::Log.log.warn { "cannot not run unknown plugin: #{plugin_name}" }
    end
  end


  def self.run_all(result, opts={})
    ScanFS::Plugins.known.each { |plugin_name|
      ScanFS::Plugins.run(plugin_name, result, opts)
    }
  end


  class Base
    include ScanFS::Log

    def self.inherited(plugin)
      ScanFS::Plugins.register(plugin)
    end

    def self.author
      "unknown"
    end

    def self.version
      "unknown"
    end

    def self.description
      "unknown"
    end

    attr_reader :result, :opts
 
    def initialize(result, opts={})
      @result = result
      @opts = opts
    end

    def run
      log.warn { "plugin routine #{self.class}##run not implemented" }
    end

  end # class Base


end # module ScanFS::Plugins
