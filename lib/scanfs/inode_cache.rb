# -*- encoding: binary -*-

require 'scanfs/ext/bloomfilter'
require 'thread'

module ScanFS::InodeCache

  @caches = []
  @cache_lock = Mutex.new

  def self.init(num_caches=8, num_salts=8)
    @cache_lock.synchronize {

      @num_caches = num_caches.to_i
      if @num_caches < 1
        @num_caches = 1
      elsif @num_caches > ScanFS::Constants::INODE_CACHE_MAX_FILTERS
        @num_caches = ScanFS::Constants::INODE_CACHE_MAX_FILTERS
      end
      @num_salts = num_salts.to_i
      @num_salts = 1 if @num_salts < 1

      @salts = ScanFS::Constants::INODE_CACHE_SALTS.sort_by{rand}[0..@num_salts-1]

      ScanFS::Log.log.info {
        "initialising inode cache: caches(#{@num_caches})"<<
        " salts(#{@salts.join(", ")})"
      }

      (0..@num_caches-1).each { |cache_index|
        cache = BloomFilter.new(
          :bits => ScanFS::Constants::INODE_CACHE_BITWIDTH,
          :salts => @salts
        )
        cache.extend(MonitorMixin)
        @caches[cache_index] = cache
      }

    }
  end

  def self.clone(inodeno)
    cache_index = inodeno % @num_caches
    @caches[cache_index].synchronize {
      @caches[cache_index].clone
    }
  end

  def self.reset(num_caches=8, num_salts=8)
    ScanFS::InodeCache.init(num_caches, num_salts)
  end

  def self.has_node?(inodeno)
    cache_index = inodeno % @num_caches
    @caches[cache_index].synchronize {
      if @caches[cache_index].include?(inodeno)
        true
      else
        @caches[cache_index].add(inodeno)
        false
      end
    }
  end


end # module ScanFS::InodeCache
