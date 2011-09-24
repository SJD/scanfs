# encoding: utf-8

SCANFS_LIB_DIR = File.join(File.dirname(__FILE__), 'lib')
$LOAD_PATH.unshift(SCANFS_LIB_DIR) unless $LOAD_PATH.include?(SCANFS_LIB_DIR)
require 'scanfs'

scanfs_description="A filesystem scanner that utilises threading to minimize IO wait.

Particularly good when:
 - using a Ruby implementation with good thread concurrency
 - scanning a filesystem resident on something like a NetApp or BlueArc filer

Not particularly good when:
 - using a Ruby implementation with poor thread concurrency
 - scanning a filesystem that resides on a single disk

Can be very memory intensive depending on your filesystem density
and/ or Ruby implementation of choice.
"

Gem::Specification.new do |s|
  s.name                = "scanfs"
  s.version             = ScanFS.version
  s.authors             = ["Sam Duncan"]
  s.email               = ["scanfs@port80.co.nz"]
  s.homepage            = "http://github.com/SJD/scanfs"
  s.summary             = "Threaded filesystem scanner"
  s.description         = scanfs_description
  s.files               = Dir.glob("{bin,lib}/**/*")
  s.require_paths       = ["lib"]
  s.executables         = ['scanfs'] 
end
