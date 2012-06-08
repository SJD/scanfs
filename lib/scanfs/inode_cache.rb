# -*- encoding: binary -*-

require 'scanfs/ext/bloominsimple'
require 'monitor'

module ScanFS::InodeCache


  @filter ||= BloominSimple.new(1_000_000)
  @monitor = Monitor.new

  def self.has_node?(node)
    @monitor.synchronize {
      if @filter.includes?(node)
        true
      else
        @filter.add(node)
        false
      end
    }
  end

  def self.clone
    @monitor.synchronize {
      @filter.clone
    }
  end

  def self.reset
    @monitor.synchronize {
      @filter = BloominSimple.new(1_000_000)
    }
  end


end # module ScanFS::InodeCache
