# -*- encoding: binary -*-

require 'etc'
require 'thread'

module ScanFS::Utils


  class Stat
    include ScanFS::Log

    attr_reader       :path

    #TODO: fix for 1.8.x support?
    # or bin the silly regex altogether somehow, hrm ...
    @@depth_regex = Regexp.new(/(?<![\\\/])\//)

    def initialize(path, opts={})
      we_have_a_weird_transience_multipass = true
      @path = path
      begin
        if opts[:assume_mountpoint]
          # st_dev is more reliable this way.
          # the option is here and used by the scanner for the root path.
          # We stat 'inside' the dir which causes the automounter to run
          # and helps to stop our ref dev no from disagreeing with every
          # single subsequent stat dev in the case where the root wasn't
          # mounted at runtime.
          # 
          @stat = File.lstat(File.join(@path, '.'))
        else
          @stat = File.lstat(@path)
        end
      rescue Errno::EACCES => e
        raise ScanFS::PermissionError.new(
          "failed to stat #{@path}: permission denied"
        )
      rescue Errno::ENOENT, Errno::ESTALE => e
        # This hack is here until I figure out why sometimes
        # lstat will return ENOENT and then a successful result
        # on an immediate retry. Kernel bug?
        # 
        # On top of that, current JRuby will return ENOENT
        # regardless of errno in a failure condition which makes
        # this hack all the more painful.
        #
        # This is also nasty if we have collected dirents and gone to stat
        # them, and in the meantime some/ all have been deleted. We will
        # be double stat'ing things that /literally/ don't exist.
        if we_have_a_weird_transience_multipass
          we_have_a_weird_transience_multipass = false
          log.debug { "weird transience multipass (#{e.class}): #{@path}" }
          retry
        else
          raise ScanFS::FileNotFoundError.new(
            "failed to stat #{@path}: file not found"
          )
        end
      end
    end

    def size; @stat.size; end
    def atime; @stat.atime; end
    def mtime; @stat.mtime; end
    def uid; @stat.uid; end
    def dev; @stat.dev; end
    def ino; @stat.ino; end
    def nlink; @stat.nlink; end
    def directory?; @stat.directory?; end
    def symlink?; @stat.symlink?; end

    def fs_depth
      @path == '/' && 0 || @path.scan(@@depth_regex).size
    end

  end # class Stat


  class Directory
    include ScanFS::Log

    META_DIRS = {'.' => true, '..' =>true}
    @@filters = META_DIRS.dup

    def self.filters
      @@filters    
    end

    def self.set_filters(*filters)
      unless filters.empty?
        @@filters.clear
        filters.each { |f| @@filters[f.dup] = true unless nil == f }
        @@filters.merge!(META_DIRS)
      end
      @@filters
    rescue StandardError => e
        ScanFS::Log.log.warn { "failed to set filters: #{e.message}" }
    end

    @@ref_epoch = Time.new.to_i
    @@age_unit = 86400*7 # seven day blocks
    @@x01_epoch = Time.at(@@ref_epoch - @@age_unit*1)
    @@x02_epoch = Time.at(@@ref_epoch - @@age_unit*2)
    @@x04_epoch = Time.at(@@ref_epoch - @@age_unit*4)
    @@x12_epoch = Time.at(@@ref_epoch - @@age_unit*12)
    @@x26_epoch = Time.at(@@ref_epoch - @@age_unit*26)
    @@x52_epoch = Time.at(@@ref_epoch - @@age_unit*52)

    def self.aging_as_of
      @@x01_epoch
    end

    attr_reader   :path, :depth, :parent, :children, :total,
                  :owner, :atime, :mtime, :dir_count, :file_count,
                  :x01, :x02, :x04, :x12, :x26, :x52,
                  :user_sizes

    def initialize(stat)
      raise ScanFS::Error.new("invalid argument: #{stat.inspect}") unless
        stat.directory?
      @path, @depth = stat.path, stat.fs_depth
      @parent, @children = nil, nil
      @owner, @total = stat.uid, stat.size
      @atime, @mtime = stat.atime, stat.mtime
      @x01 = ([stat.atime, stat.mtime].max <= @@x01_epoch)? stat.size : 0
      @x02 = ([stat.atime, stat.mtime].max <= @@x02_epoch)? stat.size : 0
      @x04 = ([stat.atime, stat.mtime].max <= @@x04_epoch)? stat.size : 0
      @x12 = ([stat.atime, stat.mtime].max <= @@x12_epoch)? stat.size : 0
      @x26 = ([stat.atime, stat.mtime].max <= @@x26_epoch)? stat.size : 0
      @x52 = ([stat.atime, stat.mtime].max <= @@x52_epoch)? stat.size : 0
      @user_sizes = {@owner => stat.size}
      @dir_count = 1
      @file_count = 0
    end

    def link_parent(parent)
      log.warn {
        "redefining parent for #{path}: #{@parent.path} <=> #{parent.path}"
      } unless nil == @parent
      (@parent = parent).link_child(self)
    end

    def link_child(child)
      (@children ||= []) <<
        child unless nil != @children && @children.include?(child)
    end; protected :link_child

    def parent_path
      if @parent
        @parent.path
      else
        File.dirname(@path)
      end
    end

    def each_child_path
      begin
        Dir.foreach(@path) { |dirent|
          next if @@filters[dirent]
          yield File.join(@path, dirent)
        }
      rescue Errno::EACCES
        raise ScanFS::PermissionError.new(
          "failed to open #{@path}: permission denied"
        )
      rescue Errno::ENOENT
        raise ScanFS::FileNotFoundError.new(
          "failed to open #{@path}: file not found"
        )
      end
    end

    def merge_user_sizes(sizes, resolve_uids=false)
      sizes.each_pair { |k,v|
        add_user_size(k, v, resolve_uids)
      }
    end

    def add_user_size(u, s, resolve_uids=false)
      u = UIDResolver.resolve(u) unless !resolve_uids # blocking
      if @user_sizes.keys.include? u
        @user_sizes[u] += s
      else
        @user_sizes[u] = s
      end
    end

    def <<(obj)
      case obj
        when Stat
          @total += obj.size
          @file_count+=1
          add_user_size(obj.uid, obj.size)
          @atime = obj.atime unless atime > obj.atime
          @mtime = obj.mtime unless mtime > obj.mtime
          unless obj.size == 0
            @x01 += obj.size if [obj.atime, obj.mtime].max <= @@x01_epoch
            @x02 += obj.size if [obj.atime, obj.mtime].max <= @@x02_epoch
            @x04 += obj.size if [obj.atime, obj.mtime].max <= @@x04_epoch
            @x12 += obj.size if [obj.atime, obj.mtime].max <= @@x12_epoch
            @x26 += obj.size if [obj.atime, obj.mtime].max <= @@x26_epoch
            @x52 += obj.size if [obj.atime, obj.mtime].max <= @@x52_epoch
          end
        when Directory
          @total += obj.total
          @dir_count += obj.dir_count
          @file_count += obj.file_count
          @atime = obj.atime unless atime > obj.atime
          @mtime = obj.mtime unless mtime > obj.mtime
          merge_user_sizes(obj.user_sizes)
          unless obj.total == 0
            @x01 += obj.x01
            @x02 += obj.x02
            @x04 += obj.x04
            @x12 += obj.x12
            @x26 += obj.x26
            @x52 += obj.x52
          end
        else
          raise TypeError.new(
            "#{self.class.name}#<< expects ScanFS::Utils::Stat or #{self.class.name}, not: #{obj.class.name} #{obj.path}"
          )
      end

      # be MINDFUL of this!
      # there are two, and only two, sane scenarios here
      #
      # a) you are walking a filesystem and linking EVERY parent as you go
      # ensuring the chain is always unbroken back to the root. In this case
      # you want to link the parent BEFORE inserting any stats. You have
      # chosen AUTOMATIC aggregation.
      #
      # OR
      #
      # b) you are cartwheeling around the filesystem linking NO parents
      # which you intend to do all of at the end. In this case you should 
      # immediately insert the stat and wait to link parents AFTER you
      # have inserted all the stats. You have chosen MANUAL aggregation.
      #
      @parent << obj unless nil == @parent

      total
    end

    def inspect
      "<#{self.class.name} #{path}:" <<
      " total=#{total} users=#{user_sizes.length}" <<
      " dir_count=#{dir_count} file_count=#{file_count}" <<
      " x01=#{@x01}" <<
      " x02=#{@x02}" <<
      " x04=#{@x04}" <<
      " x12=#{@x12}" <<
      " x26=#{@x26}" <<
      " x52=#{@x52}" <<
      ">"
    end

  end # class Directory


  class UIDResolver
    include ScanFS::Log

    @@uid_cache ||= {}
    #TODO: should really have a non-blocking read lock
    @@uid_cache_lock = Mutex.new

    def self.resolve(uid)
      @@uid_cache_lock.synchronize {
        begin
          if nil == @@uid_cache[uid]
            @@uid_cache[uid] = Etc.getpwuid(uid).name
          end
          @@uid_cache[uid]
        rescue ArgumentError
          log.debug {
            "#{self.class} failed to resolve username for uid: #{uid}"
          }
          @@uid_cache[uid] = uid
        end
      }
    end

  end # class UIDResolver


  class BasicOutput
    include ScanFS::Log

    def initialize(result, opts={})
      @result = result
      @opts = opts
      self
    end

    def show
      if @result.root.nil?
        log.error { "Failed to produce result!" }
      else
        log.debug { "building basic report: #{@result.root.inspect}" }
        out = ["Scanned #{@result.root.path} in #{@result.scan_time} seconds"]
        out << "    Owner: #{UIDResolver.resolve(@result.root.owner)}"
        out << "    Total Size: #{@result.root.total}"
        out << "    Dir Count: #{@result.root.dir_count}"
        out << "    File Count: #{@result.root.file_count}"
        out << "    ATime: #{@result.root.atime}"
        out << "    MTime: #{@result.root.mtime}"
        out << "    One Week: #{@result.root.x01}"
        out << "    Two Weeks: #{@result.root.x02}"
        out << "    Four Weeks: #{@result.root.x04}"
        out << "    Twelve Weeks: #{@result.root.x12}"
        out << "    Twenty Six Weeks: #{@result.root.x26}"
        out << "    Fifty Two Weeks: #{@result.root.x52}"
        if @opts[:debug] && @result.root.children
          out << "    Children:\n      "+
	       "#{@result.root.children.map(&:inspect).join("\n      ")}"
        end
        if @opts[:user_sizes]
          out << "    User Sizes:"
          @result.root.user_sizes.to_a.sort {
            |a,b| a[1] <=> b[1]  # ordered by size
          }.reverse.each { |u|   # ... descending
            out << "        - #{UIDResolver.resolve(u[0])} => #{u[1]}"
          }
        end
        log.unknown { out.join("\n") } unless @opts[:logfile].nil?
        puts out.join("\n")
      end
    end

  end # class BasicOutput


end # module ScanFS::Utils
