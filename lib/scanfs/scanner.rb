# -*- encoding: binary -*-

require 'thread'
require 'monitor'
require 'timeout'

module ScanFS


  class ScanResult
    include ScanFS::Log

    attr_reader :root, :data, :scan_time

    def initialize(data={}, scan_time=0)
      @data = data.freeze
      @scan_time = scan_time.freeze
      @root = @data[depths.min].values.first
    end

    def depths
      @depths ||= @data.keys.sort
    end

    def breadth_at(depth)
      @data[depth].size
    end

  end # class ScanResult


  class Scanner
    include ScanFS::Log

    #TODO: investigate viability of removing
    # Thread::exclusive dependencies

    WATCH_LOOP = 1
    WORKER_TIMEOUT = 3

    DEFAULT_TARGET = File.expand_path('.')
    DEFAULT_THREAD_MAX = 8
    DEFAULT_SETUP_TIMEOUT = 3

    IDLE = 0
    FLAG = 1
    SCAN = 2

    def initialize(target, opts={})
      @terminate = false
      @scanning = false
      @scanner_lock = Mutex.new

      @workers = []
      @worker_next_id = 1

      @inode_cache = Hash.new { |h,k| h[k] = {} }.extend(MonitorMixin)
      @inode_cache_merge = Proc.new { |d, c1, c2| c1.merge!(c2) }
      #@inode_cache_lock = Mutex.new

      @scan_queue = [].extend(MonitorMixin)
      @scan_queue_populated = @scan_queue.new_cond
      # as a general rule never touch this outside of @scan_queue#synchronize
      @jobs_dispatched = {}
      @jobs_dispatched.default = IDLE

      @result_queue = [].extend(MonitorMixin)
      @result_queue_populated = @result_queue.new_cond
      @results = {}

      Thread.abort_on_exception =
        @debug = (opts[:debug]) ? true : false

      @thread_max = DEFAULT_THREAD_MAX
      if opts[:thread_max] &&
        nil == (@thread_max = positive_int_value(opts[:thread_max]))
        raise ScanFS::Error.new("thread max must be a positive integer")
      end

      @setup_timeout = DEFAULT_SETUP_TIMEOUT
      if opts[:setup_timeout] &&
        nil == (@setup_timeout = positive_int_value(opts[:setup_timeout]))
        raise ScanFS::Error.new("setup_timeout must be a positive integer")
      end

      @opts = opts
      prepare_target(target)

    rescue ScanFS::Error => e
      raise ScanFS::Error.new("scanner bootstrap failed: #{e.message}")
    end

    def positive_int_value(value)
      return value.to_i if value.respond_to?(:to_i) && value.to_i > 0
      nil
    end

    def terminate!
      @scanner_lock.synchronize { @terminate = true }
    end

    def terminate?
      @scanner_lock.synchronize { true == @terminate }
    end

    def scanning=(bool)
      @scanner_lock.synchronize {
        requested = (bool) ? true : false
        if requested && true == @scanning # we are already scanning
          raise ScanFS::Error.new("already scanning")
        end
        @scanning = requested
      }
    end; private :scanning=

    def scanning?
      @scanner_lock.synchronize { true == @scanning }
    end

    def target
      @scanner_lock.synchronize { @target }
    end

    def target=(target)
      @scanner_lock.synchronize {
        if @scanning
          raise ScanFS::Error.new("cannot change target mid scan")
        end
        prepare_target(target)
      }
    end

    def debug
      @scanner_lock.synchronize { @debug }
    end

    def debug=(bool)
      requested = (bool) ? true : false
      @scanner_lock.synchronize {
        @debug = requested
        log.debug { "set debug: #{@debug}" }
      }
    end

    def thread_max
      @scanner_lock.synchronize { @thread_max }
    end

    def thread_max=(value)
      raise ScanFS::Error.new(
        "thread max value must be a positive integer"
      ) if nil == positive_int_value(value)
      @scanner_lock.synchronize {
        @thread_max = positive_int_value(value)
        log.info { "set thread max: #{@thread_max}" }
      }
    end

    def setup_timeout
      @scanner_lock.synchronize { @setup_timeout }
    end

    def setup_timeout=(value)
      raise ScanFS::Error.new(
        "setup timeout value must be a positive integer"
      ) if nil == positive_int_value(value)
      @scanner_lock.synchronize {
        @setup_timeout = positive_int_value(value)
        log.info { "set setup timeout: #{@setup_timeout}" }
      }
    end

    def reset
      Thread.exclusive {
        @terminate = false
        @workers.each { |w| w.kill if w.alive? }
        @workers.clear
        @worker_next_id = 1
        @inode_cache.clear
        @scan_queue.clear
        @jobs_dispatched.clear
        @result_queue.clear
        @results.clear
      }    
    end

    def next_worker_name
      @scanner_lock.synchronize {
        name = "worker-#{@worker_next_id}"
        @worker_next_id+=1
        name
      }
    end

    def check_target_device(device)
      @scanner_lock.synchronize {
        restat = ScanFS::Utils::Stat.new(@target, :assume_mountpoint => true)
        unless restat.dev == @target_device
          # autofs pulled the rug out
          log.warn {
            "target filesystem device has switched:"+
            " #{@target_device} => #{restat.dev}"
          }
          @target_device = restat.dev
        end
        @target_device
      }
    end

    def is_duplicate_inode?(stat)
      @inode_cache.synchronize {
        if @inode_cache[stat.dev] && @inode_cache[stat.dev][stat.ino]
          Thread.current[:inode_cache].merge!(@inode_cache, &@inode_cache_merge)
          true
        else
          @inode_cache[stat.dev] ||= {}
          @inode_cache[stat.dev][stat.ino] = true
          Thread.current[:inode_cache].merge!(@inode_cache, &@inode_cache_merge)
          false
        end
      }
    end

    def launch_workers
      Thread.exclusive {
        log.info { "launching #{@thread_max} workers" }
        @thread_max.times {
          @workers << Thread.new {
            ScanFS::Worker.new(self, @target_device, @opts).run
          }
        }
      }
    end; private :launch_workers

    def stop_workers
      Thread.exclusive {
        return if @workers.empty?
        log.info { "stopping workers" }
        flags = []
        @workers.size.times { flags.push ScanFS::WorkerStopFlag.new }
        push_targets(*flags)
      }
      @scanner_lock.synchronize {
        @workers.each { |w|
          next unless w.alive?
          joined = w.join(WORKER_TIMEOUT) 
          unless joined
            log.warn { "killing unresponsive worker" }
            w.kill rescue ThreadError
          end
        }
      }
    end; private :stop_workers

    def push_targets(*targets)
      @scan_queue.synchronize {
        @scan_queue.push(*targets)
        @scan_queue_populated.broadcast
      }
    end

    def report_idle
      @scan_queue.synchronize { @jobs_dispatched[Thread.current] = IDLE }
    end

    def pop_target(timeout=nil)
      @scan_queue.synchronize {
        if @scan_queue.empty?
          @jobs_dispatched[Thread.current] = IDLE
          @scan_queue_populated.wait timeout
        end
        next_target = @scan_queue.pop
        @jobs_dispatched[Thread.current] = case next_target
          when nil then IDLE
          when ScanFS::WorkerFlag then FLAG
          else
            SCAN
        end
        next_target
      }
    end

    def push_results(results)
      @result_queue.synchronize {
        @result_queue.push results
        @result_queue_populated.broadcast
      }
    end

    def prepare_target(target)
      raise ScanFS::Error.new("target cannot be nil") if nil == target
      if target.respond_to?(:path) # can be Dir object etc
        target = target.path
      elsif target.kind_of?(String)
        target = target.dup
      else
        raise ScanFS::Error.new("invalid scan target: #{target}")
      end
      log.debug { "preparing scan target: #{target}" }
      @target = File.expand_path(target)
      if DEFAULT_TARGET == @target
        log.debug { "using default target: #{DEFAULT_TARGET}" }
      end
      Timeout.timeout(@setup_timeout) {
        Dir.chdir @target
        @target_stat = ScanFS::Utils::Stat.new(
          @target,
          :assume_mountpoint => true
        )
      }
      @target_depth = @target_stat.fs_depth
      @target_device = @target_stat.dev
      log.info {
      "scan target prepared: path(#{@target})"+
      " depth(#{@target_depth}) device(#{@target_device})"
      }
      @target
    rescue Errno::ENOENT
      raise ScanFS::FileNotFoundError.new("no such directory: #{@target}")
    rescue Errno::ENOTDIR
      raise ScanFS::TypeError.new("not a directory: #{@target}")
    rescue Errno::EACCES
      raise ScanFS::PermissionError.new("permission denied: #{@target}")
    rescue Timeout::Error
      raise ScanFS::TimeoutError.new("timed out entering: #{@target}")
    end; private :prepare_target

    def scans_complete
      @scan_queue.synchronize {
        if @scan_queue.empty? && [IDLE] == @jobs_dispatched.values.uniq
          true
        else
          false
        end
      }
    end; private :scans_complete

    def merge_results
      Thread.exclusive {
        log.info { "merging results" }
        started = Time.now.to_f
        log.debug { "result queue size: #{@result_queue.size}" }
        num_results = 0
        while result = @result_queue.pop
          log.debug { "merging result fragment, depths: #{result.keys.size}" }
          result.each_pair { |depth, scans|
            @results[depth] ||= {}
            scans.each_pair { |path, directory|
              @results[depth][path] = directory
              num_results+=1
            }
          }
        end
        log.info {
          "merged #{num_results} results in #{Time.now.to_f-started} seconds"
        }
      }
    end; private :merge_results

    def aggregate_results
      Thread.exclusive {
        log.info { "aggregating results" }
        started = Time.now.to_f
        depths = @results.keys.sort.reverse
        log.debug { "result depths: #{depths.join(", ")}" }
        depths.each { |depth|
          parent_depth = depth-1
          if depth == @target_depth
            log.debug {
              "aggregation reached target: depth(#{depth})"+
              " breadth(#{@results[depth].size})"
            }
            break
          elsif !depths.include?(parent_depth)
            log.error {
              "aggregation depth chain broken: #{depth} <=> #{parent_depth}"
            }
          end
          log.debug {
            "aggregating: depth(#{depth}) breadth(#{@results[depth].size})"
          }
          @results[depth].each_pair { |path, directory|
            directory.link_parent(
              @results[parent_depth][directory.parent_path]
            )
            begin
              directory.parent << directory
            rescue NoMethodError
              log.error { "orphaned directory: #{directory.path}" }
              next
            end
          }
        }
        log.info {
          "aggregated #{depths.size} depths in #{Time.now.to_f-started} seconds"
        }
      }
    end; private :aggregate_results

    def scan

      begin
        scan_initiated = (scanning = true)
      rescue ScanFS::Error => e
        log.warn { "failed to initiate scan: #{e.message}" }
        scan_initiated = false
      end
      return nil unless scan_initiated

      reset
      push_targets ScanFS::Utils::Directory.new(@target_stat)
      @time_started = Time.now
      log.info { "scanning #{@target} started at #{@time_started}" }

      launch_workers
      until scans_complete || terminate?
        # do house keeping
        sleep WATCH_LOOP
      end
      stop_workers

      elapsed = Time.now.to_f - @time_started.to_f
      log.info { "Scanning #{@target} completed in #{elapsed} seconds" }

      merge_results
      aggregate_results

      return ScanResult.new(@results, elapsed) unless nil == @results
      raise ScanFS::Error.new("failed to produce scan result")

    ensure
      scanning = false if scan_initiated

    end

  end # class Scanner


end # module ScanFS
