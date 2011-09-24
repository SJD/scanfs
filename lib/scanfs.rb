# -*- encoding: binary -*-

module ScanFS

  VERSION_MAJOR = 0
  VERSION_MINOR = 0
  VERSION_POINT = 6

  def self.version
    "%d.%d.%d" % [
    ScanFS::VERSION_MAJOR,
    ScanFS::VERSION_MINOR,
    ScanFS::VERSION_POINT
    ]
  end

end # module ScanFS

require 'scanfs/constants'
require 'scanfs/base'
require 'scanfs/log'
require 'scanfs/nls'
require 'scanfs/utils'
require 'scanfs/worker'
require 'scanfs/scanner'
require 'scanfs/plugins'