# -*- encoding: binary -*-

require 'thread'

module ScanFS


  class Worker
    include ScanFS::Log

    OFFLOAD_THRESHOLD = 1024

    def initialize(master, fs_device, opts={})
      @master = master
      @fs_device = fs_device
      @opts = opts

      @timeout = 1
      @running = false
      #TODO: remove Worker class knowledge of master internals
      @name = @master.next_worker_name # blocking

      # thread local - no locks
      Thread.current[:inode_cache] = {}
      Thread.current[:inode_cache].default = {}
      Thread.current[:pending_scans] = []
      Thread.current[:pending_results] = {}

      # accounting
      @scans_dispatched = 0
      @scans_completed = 0
      @stat_ops = 0
      @bytes_seen = 0

      self
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
      summary = "#{@name} workload: dispatched(#{@scans_dispatched})"+
      " completed(#{@scans_completed})"+
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

    def deliver_pending_scans
      unless Thread.current[:pending_scans].empty?
        log.debug {
          "#{@name} delivering #{Thread.current[:pending_scans].count} scans"
        }
        @master.push_scans(*Thread.current[:pending_scans]) # blocking
        Thread.current[:pending_scans] = []
      end
    end; private :deliver_pending_scans

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
      case @scan
        when ScanFS::WorkerStopFlag then
          stop_running
          @scan = nil
        else
          log.debug { "#{@name} encountered unknown flag: #{@scan.class}" }
      end
    end; private :handle_worker_flag

    def report_idle
      @master.report_idle
    end; private :report_idle

    def get_scan
      begin    
        @scan = @master.pop_scan @timeout
        if @scan.kind_of? ScanFS::WorkerFlag
          handle_worker_flag
        end
      rescue ThreadError => e
        log.warn { "#{@name} ThreadError: #{e.message}" }
        @scan = nil
      end
    end; private :get_scan

    def do_scan
      unless @scan
        @scan_started = nil
      else
        log.debug { "#{@name} scanning #{@scan.path}" }
        @scans_dispatched += 1
        @scan_started = Time.now.to_f
        begin
          aggregate = ScanFS::Utils::Aggregate.new @scan.path
          aggregate << @scan
          child_count = 0
          aggregate.each_child_path { |path|
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
              Thread.current[:pending_scans].push stat
              @bytes_seen += stat.size
              child_count+= 1
              if child_count >= OFFLOAD_THRESHOLD
                log.debug { "#{@name} preemptive offload" }
                deliver_pending_scans
                child_count = 0
              end
            else
              if is_duplicate_inode?(stat)
                log.debug { "#{@name} duplicate inode detected: #{stat.path}" }
              else
                aggregate << stat
                @bytes_seen += stat.size
              end
            end
          }
          deliver_pending_scans
          depth = @scan.fs_depth
          Thread.current[:pending_results][depth] ||= {} # pre-partitioned
          Thread.current[:pending_results][depth][@scan.path] = aggregate
          @scans_completed += 1
        rescue ScanFS::Error => e
          log.warn "#{@name} #{e.message}"
        rescue StandardError => e
          log.warn {
            "#{@name} failed to scan #{@scan.path}:" <<
            " #{e.message}\n#{e.backtrace.join("\n")}"
          }
          @scan_started = nil
        end
      end
    end; private :do_scan

    def run
      start_running
      while running?
        get_scan
        do_scan
      end
      log.debug { "#{@name} exiting normally" }
    ensure
      deliver_pending_scans
      deliver_pending_results
      summarise_workload
      report_idle
    end

  end # class Worker


end # module ScanFS
