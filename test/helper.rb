require 'test/unit'

lib_dir = File.join(File.dirname(__FILE__),'..','lib')
$:.unshift lib_dir unless $:.include?(lib_dir)
require 'scanfs'
