# -*- encoding: binary -*-

require 'optparse'

module ScanFS

  #TODO: put these somewhere?
  class Error < StandardError; end
  class TypeError < Error; end
  class TimeoutError < Error; end
  class PermissionError < Error; end
  class FileNotFoundError < Error; end

  class WorkerFlag; end
  class WorkerStopFlag < WorkerFlag; end

  @@ret = 0
  @@progname = File.basename("#{$0}", ".rb")
  @@options = {}
  @@target = Dir.pwd
  @@profiling = false

  def self.init

    banner = "Usage: #{@@progname} [options] <target dir>"
    optparse = OptionParser.new(banner) { |opts|

      opts.separator("\n")
      help_help = "Display help and exit"
      opts.on( "-h", "--help", help_help ) {
        puts opts; exit 0
      }
      version_help = "Display version and exit"
      opts.on( "--version", version_help ) {
        puts version; exit 0
      }

      opts.separator("\nScanning")
      thread_max_default = ScanFS::Scanner::DEFAULT_THREAD_MAX
      thread_max_help = "Num worker threads (Default: #{thread_max_default})"
      opts.on( "-t", "--threads INT", Integer, thread_max_help ) { |n|
        @@options[:thread_max] = n
      }
      filter_help = "Skip paths containing FILTER. Multiple filters can be"+
        " specified as a comma separated list, ie; FILTER1,FILTER2,FILTER3 ..."
      opts.on( "-f", "--filter FILTER", Array, filter_help ) { |filter_list|
        @@options[:filter] = filter_list
      }

      opts.separator("\nOutput")
      quiet_help = "Run quietly"
      opts.on( "-q", "--quiet", quiet_help ) {
        @@options[:quiet] = true
      }
      verbose_help = "Run verbosely"
      opts.on( "-v", "--verbose", verbose_help ) {
        @@options[:verbose] = true
      }
      debug_help = "Run in debug mode"
      opts.on( "-d", "--debug", debug_help ) {
        @@options[:debug] = true
      }
      logfile_help = "Log to FILE (Default: STDOUT)"
      opts.on( "-l", "--logfile FILE", logfile_help ) { |f|
        @@options[:logfile] = f
      }
      user_sizes_help = "Display user sizes"
      opts.on( "-u", "--user-sizes", user_sizes_help ) {
        @@options[:user_sizes] = true
      }

      opts.separator("\nPlugins")
      plugin_help = "Run PLUGIN on the scan result. Multiple plugins can be"+
        " specifed as a comma separated list, ie; PLUGIN1,PLUGIN2,PLUGIN3 ..."
      opts.on( "-p", "--plugin PLUGIN", Array, plugin_help ) { |plugin_list|
        @@options[:plugins] = plugin_list
      }
      list_plugins_help = "List known plugins and exit"
      opts.on( "--list-plugins", list_plugins_help ) {
        @@options[:list_plugins] = true
      }
      plugin_dir_default = File.join(ScanFS::Constants::USER_DIR, 'plugins')
      plugin_dir_help = "Load plugins from DIR (Default: #{plugin_dir_default})"
      opts.on( "--plugin-dir DIR", plugin_dir_help ) { |d|
        @@options[:plugin_dir] = d
      }
      disable_plugins_help = "Disable all plugins"
      opts.on( "--disable-plugins", disable_plugins_help ) {
        @@options[:disable_plugins] = true
      }

      opts.separator("\nProfiling")
      ruby_prof_help = "Apply ruby-prof to scan"
      opts.on( "--ruby-profile", ruby_prof_help ) {
        begin
          require 'ruby-prof'
        rescue LoadError => e
          warn "Ruby Profiler unavailable: #{e}"; exit 1
        end
        @@options[:profile] = :ruby_prof
        @@profiling = true
      }
      rbx_prof_help = "Apply Rubinius::Profiler to scan"
      opts.on( "--rbx-profile", rbx_prof_help ) {
        unless ScanFS::Constants::ENGINE == 'rbx'
          warn "Rubinius Profiler unavailable"; exit 1
        end
        begin
          require 'profiler'
        rescue LoadError => e
          warn "Ruby Profiler unavailable: #{e}"; exit 1
        end
        @@options[:profile] = :rbx_prof
        @@profiling = true
      }
    }

    tmp_argv = ARGV.dup
    if defined?(ENV['SCANFS_OPTS']) && ![nil, ""].include?(ENV['SCANFS_OPTS'])
      tmp_argv += ENV['SCANFS_OPTS'].split
    end

    begin
      optparse.parse!(tmp_argv)
    rescue OptionParser::ParseError => e
      warn "#{e}"; exit 1    
    end

    begin
      ScanFS::Log.configure(@@options)
    rescue ScanFS::Error => e
      warn "#{e}"; exit 1
    end

    identifier = "#{@@progname}-#{ScanFS.version}"
    ScanFS::Log.log.debug { "="*(identifier.size+1) }
    ScanFS::Log.log.debug { identifier }
    ScanFS::Log.log.debug { "="*(identifier.size+1) }
    ScanFS::Log.log.debug { "runtime: #{RUBY_DESCRIPTION}" }
    ScanFS::Log.log.debug { "environment options: \"#{ENV['SCANFS_OPTS']}\"" }
    ScanFS::Log.log.debug { "command line options: #{ARGV.inspect}" }
    ScanFS::Log.log.debug { "interpolated options: #{@@options.inspect}" }

    unless @@options[:disable_plugins]
      plugin_dir = @@options[:plugin_dir] || ScanFS::Plugins::USER_PLUGIN_DIR
      plugins_loaded = ScanFS::Plugins.load_all(plugin_dir)
      if !plugins_loaded
        warn "failed to load one or more plugins"
      end
      unless @@options[:plugins].nil?
        @@options[:plugins].each { |plugin_name|
          unless ScanFS::Plugins.known.include?(plugin_name)
            warn "unknown plugin requested: #{plugin_name}"; exit 1
          end
        }
      end
    end

    if @@options[:filter]
      ScanFS::Utils::Directory.set_filters(*@@options[:filter])
      ScanFS::Log.log.info {
        "active filters: #{@@options[:filter].join(', ')}"
      }
    end

    if @@options[:list_plugins]
      puts "Known plugins:"
      ScanFS::Plugins.known.each { |plugin_name|
        if (info = ScanFS::Plugins.info(plugin_name)).nil?
          ScanFS::Log.log.debug { "no info for plugin: #{plugin_name}" }
          next
        end
        puts "\n  Name: #{plugin_name}"
        puts "  Author: #{info[:author]}"
        puts "  Version: #{info[:version]}"
        puts "  Description: #{info[:description]}"
      }
      exit 1;
    end

    if nil == tmp_argv || tmp_argv.empty?
      warn "no <target dir> specified, assuming cwd: #{@@target}"
    else
      @@target = tmp_argv.shift
    end 

  end

  def self.start_profiler
    return unless @@profiling
    case @@options[:profile]
      when :ruby_prof
        RubyProf.start
      when :rbx_prof
        @@profiling = Rubinius::Profiler::Instrumenter.new
        @@profiling.start
    end
  end

  def self.stop_profiler
    return unless @@profiling
    case @@options[:profile]
      when :ruby_prof
        r = RubyProf.stop
        p = RubyProf::FlatPrinter.new(r)
        p.print(STDERR)
      when :rbx_prof
        @@profiling.stop
        @@profiling.show(STDERR)
    end
  end

  def self.run()

    ScanFS::start_profiler
    scanner = ScanFS::Scanner.new(@@target, @@options)
    result = scanner.scan
    ScanFS::stop_profiler

    unless @@options[:plugins].nil? || @@options[:disable_plugins]
      @@options[:plugins].each { |plugin_name|
        ScanFS::Plugins.run(plugin_name, result, @@options)
      }
    end

    output = ScanFS::Utils::BasicOutput.new(result, @@options)
    output.show

  rescue ScanFS::Error => e
    warn "#{Time.now} -- #{e.message}"
    @@ret = 2

  rescue StandardError => e
    warn "#{Time.now} -- Unhandled exception: " <<
      "#{e.message}\n#{e.backtrace.join("\n")}"
    @@ret = 3

  rescue Exception => e
    warn "Exception: #{e}"
    warn "#{e.inspect}"
    warn "#{e.backtrace.join("\n")}"
    raise

  ensure
    exit(@@ret)

end


end # module ScanFS
