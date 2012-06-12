# -*- encoding: binary -*-

require 'scanfs/ext/bloomfilter'
require 'thread'

module ScanFS::InodeCache


  @filters = []
  @cache_lock = Mutex.new

  def self.init_filters
    @cache_lock.synchronize {
      (0..8).each { |filter_index|
        filter = BloomFilter.new(:bits => 0xffffff, :salts => 'a'..'f')
        filter.extend(MonitorMixin)
        @filters[filter_index] = filter
      }
    }
  end

  def self.clone(inodeno)
    filter_index = inodeno % 9
    @filters[filter_index].synchronize {
      @filters[filter_index].clone
    }
  end

  def self.reset
    ScanFS::InodeCache.init_filters
  end

  def self.has_node?(inodeno)
    filter_index = inodeno % 9
    @filters[filter_index].synchronize {
      if @filters[filter_index].include?(inodeno)
        true
      else
        @filters[filter_index].add(inodeno)
        false
      end
    }
  end

  ScanFS::InodeCache.init_filters


end # module ScanFS::InodeCache
