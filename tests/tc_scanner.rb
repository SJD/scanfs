$: << File.dirname(__FILE__) unless $:.include?(File.dirname(__FILE__))
require 'test_helper'
require 'thread'
require 'set'

class TC_Scanner < Test::Unit::TestCase

  def setup
    @fake_logger = Logger.new(STDERR)
    @fake_logger.level = Logger::UNKNOWN+1
    ScanFS::Log.device = @fake_logger
    @fake_target = File.join('dev', 'scanfs')
    @real_target = File.expand_path('.')
    @default_scanner = ScanFS::Scanner.new(@real_target)
    @optioned_scanner = ScanFS::Scanner.new(
      @real_target,
      :debug=>true,
      :thread_max=>999,
      :setup_timeout=>999
    )
    @ref_stat = File.lstat(@real_target)
    Thread.current[:inode_cache] = {}
    Thread.current[:inode_cache].default = {}
  end

  def test_options
    assert_same(
      true,
      @optioned_scanner.debug,
      "can initialise debug to true"
    )
    assert_same(
      Thread.abort_on_exception,
      @optioned_scanner.debug,
      "debug initialised to true turns on Thread.abort_on_exception"
    )
    assert_same(
      false,
      @default_scanner.debug,
      "default debug is false"
    )
    assert_equal(
      999,
      @optioned_scanner.thread_max,
      "can initialise thread max to positive integer"
    )
    assert_equal(
      999,
      @optioned_scanner.thread_max,
      "can initialise thread max to positive integer with string"
    )
    assert_raise(ScanFS::Error) {
      ScanFS::Scanner.new(@real_target, :thread_max=>0 )
    }
    assert_same(
      ScanFS::Scanner::DEFAULT_THREAD_MAX,
      @default_scanner.thread_max,
      "default thread max is ScanFS::Scanner::DEFAULT_THREAD_MAX"
    )
    assert_equal(
      999,
      @optioned_scanner.setup_timeout,
      "can initialise setup timeout to positive integer"
    )
    assert_raise(ScanFS::Error) {
      ScanFS::Scanner.new(@real_target,:setup_timeout=>0 )
    }
    assert_same(
      ScanFS::Scanner::DEFAULT_SETUP_TIMEOUT,
      @default_scanner.setup_timeout,
      "default setup_timeout is ScanFS::Scanner::DEFAULT_SETUP_TIMEOUT"
    )
    assert_equal(
      false,
      @default_scanner.terminate?,
      "scanner is not terminated by default"
    )
  end

  def test_public_interface
    assert_not_equal(
      @default_scanner.next_worker_name,
      @default_scanner.next_worker_name,
      "worker names are unique"
    )
    assert_same(
      false,
      @default_scanner.scanning?,
      "scanner is not scanning"
    )
    assert_same(
      true,
      @default_scanner.debug = true,
      "can set debug to true"
    )
    assert_equal(
      999,
      @default_scanner.thread_max = 999,
      "can set thread max to positive integer"
    )
    assert_equal(
      999,
      @default_scanner.setup_timeout = 999,
      "can set setup timeout to positive integer"
    )
    assert_equal(
      true,
      @default_scanner.terminate!,
      "can set scanner terminate!"
    )
    assert_equal(
      false,
      @default_scanner.is_duplicate_inode?(@ref_stat) &&
        @default_scanner.is_duplicate_inode?(@ref_stat),
      "same stat twice is invalid"
    )
    assert_equal(
      @real_target,
      @default_scanner.target = @real_target,
      "can set target to real value"
    )
    assert_raise(ScanFS::Error) { @default_scanner.target = nil }
  end


end # class TC_Scanner
