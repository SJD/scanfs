# -*- encoding: binary -*-

require 'thread'

module ScanFS


  class Worker
    include ScanFS::Log

    DEFAULT_TIMEOUT = 1
    DEFAULT_OFFLOAD_THRESHOLD = 1024

    def initialize(master, fs_device, opts={})
      @timeout = DEFAULT_TIMEOUT
      @running = false

      @master = master
      @name = @master.next_worker_name # blocking
      @fs_device = fs_device
      @opts = opts

      # thread local - no locks
      Thread.current[:inode_cache] = {}
      Thread.current[:inode_cache].default = {}
      Thread.current[:pending_targets] = []
      Thread.current[:pending_results] = {}

      # accounting
      @targets_dispatched = 0
      @targets_completed = 0
      @stat_ops = 0
      @bytes_seen = 0
    end

    def running?
      @running == true
    end; private :running?

    def start_running
      @running = true
      @started_at = Time.now.to_f
      log.debug { "#{@name} starting" }
    end; private :start_running

    def stop_running
      @running = false
      @stopped_at = Time.now.to_f
      log.debug { "#{@name} stopping" }
    end; private :stop_running

    def summarise_workload
      summary = "#{@name} workload: dispatched(#{@targets_dispatched})"+
      " completed(#{@targets_completed})"+
      " stat_ops(#{@stat_ops})"+
      " stat_ops_sec(#{@stat_ops/ (@stopped_at - @started_at)})"+
      " bytes_seen(#{@bytes_seen})"
      log.info { summary }
    end

    def deliver_pending_results
      unless Thread.current[:pending_results].empty?
        log.debug {
          "#{@name} delivering #{Thread.current[:pending_results].size} results"
        }
        @master.push_results Thread.current[:pending_results] # blocking
      end
    end

    def deliver_pending_targets
      unless Thread.current[:pending_targets].empty?
        log.debug {
          "#{@name} delivering #{Thread.current[:pending_targets].size} targets"
        }
        @master.push_targets(*Thread.current[:pending_targets]) # blocking
        Thread.current[:pending_targets] = []
      end
    end; private :deliver_pending_targets

    def is_same_filesystem?(stat)
      if stat.dev != @fs_device
        # we better check we aren't out of date
        @fs_device = @master.check_target_device(@fs_device) # blocking
        stat.dev == @fs_device
      else
        true
      end
    end

    def is_duplicate_inode?(stat)
      if stat.nlink > 1
        if Thread.current[:inode_cache][stat.dev][stat.ino]
          true
        else
          @master.is_duplicate_inode? stat # blocking
        end
      else
        false
      end
    end

    def handle_worker_flag
      case @target
        when ScanFS::WorkerStopFlag then
          stop_running
          @target = nil
        else
          log.debug { "#{@name} encountered unknown flag: #{@target.class}" }
      end
    end; private :handle_worker_flag

    def report_idle
      @master.report_idle
    end; private :report_idle

    def get_target
      begin    
        @target = @master.pop_target @timeout
        if @target.kind_of? ScanFS::WorkerFlag
          handle_worker_flag
        end
      rescue ThreadError => e
        log.warn { "#{@name} ThreadError: #{e.message}" }
        @target = nil
      end
    end; private :get_target

    def do_scan
      unless @target
        @scan_started = nil
      else
        log.debug { "#{@name} scanning #{@target.path}" }
        @targets_dispatched += 1
        @scan_started = Time.now.to_f
        begin
          child_count = 0
          @target.each_child_path { |path|
            begin
              stat = ScanFS::Utils::Stat.new path
              @stat_ops += 1
            rescue ScanFS::Error => e
              log.warn "#{@name} #{e.message}"
              next
            end
            unless is_same_filesystem?(stat)
              log.info {
                "cross filesystem node detected: expected(#{@fs_device})"+
                " actual(#{stat.dev}) path(#{stat.path})"
              }
              next
            end
            if stat.directory?
              Thread.current[:pending_targets].push(
                ScanFS::Utils::Directory.new(stat)
              )
              @bytes_seen += stat.size
              child_count+= 1
              if child_count >= DEFAULT_OFFLOAD_THRESHOLD
                log.debug { "#{@name} preemptive offload" }
                deliver_pending_targets
                child_count = 0
              end
            else
              if is_duplicate_inode?(stat)
                log.debug { "#{@name} duplicate inode detected: #{stat.path}" }
              else
                @target << stat
                @bytes_seen += stat.size
              end
            end
          }
          deliver_pending_targets
          # pre-partitioned
          Thread.current[:pending_results][@target.depth] ||= {}
          Thread.current[:pending_results][@target.depth][@target.path] =
            @target
          @targets_completed += 1
        rescue ScanFS::Error => e
          log.warn "#{@name} #{e.message}"
        rescue StandardError => e
          log.warn {
            "#{@name} failed to scan #{@target.path}:" <<
            " #{e.message}\n#{e.backtrace.join("\n")}"
          }
          @scan_started = nil
        end
      end
    end; private :do_scan

    def run
      start_running
      while running?
        get_target
        do_scan
      end
      log.debug { "#{@name} exiting normally" }
    ensure
      stop_running if running?
      deliver_pending_targets
      deliver_pending_results
      summarise_workload
      report_idle
    end

  end # class Worker


end # module ScanFS
