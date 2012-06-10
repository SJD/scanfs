# -*- encoding: binary -*-

require 'thread'

module ScanFS::InodeCache


  @filter = []
  @mutex = Mutex.new

  def self.has_node?(node)
    @mutex.synchronize {
      if 1 == @filter[node]
        true
      else
        @filter[node] = 1
        false
      end
    }
  end

  def self.clone
    @mutex.synchronize {
      @filter.clone
    }
  end

  def self.reset
    @mutex.synchronize {
      @filter = []
    }
  end


end # module ScanFS::InodeCache
