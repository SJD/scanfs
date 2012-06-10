#!/usr/bin/env ruby

$:.unshift File.dirname(__FILE__)
require 'helper'

class TestInodeCache < Test::Unit::TestCase

  def setup
    ScanFS::InodeCache.reset
    @test_inode_1 = File.lstat(__FILE__).ino
    @test_inode_2 = File.lstat( File.dirname(__FILE__) ).ino
  end

  def test_membership
    assert( !ScanFS::InodeCache.has_node?(@test_inode_1), "Reset inode cache does not contain #{@test_inode_1}" )
    assert( ScanFS::InodeCache.has_node?(@test_inode_1), "Inode cache now contains #{@test_inode_1}" )
    assert( !ScanFS::InodeCache.has_node?(@test_inode_2), "Reset inode cache does not contain #{@test_inode_2}" )
    assert( ScanFS::InodeCache.has_node?(@test_inode_2), "Inode cache now contains #{@test_inode_2}" )
  end

  def test_reset
    assert( !ScanFS::InodeCache.has_node?(@test_inode_1), "Reset inode cache does not contain #{@test_inode_1}" )
    assert( ScanFS::InodeCache.has_node?(@test_inode_1), "Inode cache now contains #{@test_inode_1}" )
    ScanFS::InodeCache.reset
    assert( !ScanFS::InodeCache.has_node?(@test_inode_1), "Reset inode cache does not contain #{@test_inode_1}" )
  end

  def test_clone
    assert( !ScanFS::InodeCache.has_node?(@test_inode_1), "Reset inode cache does not contain #{@test_inode_1}" )
    assert( ScanFS::InodeCache.has_node?(@test_inode_1), "Inode cache now contains #{@test_inode_1}" )
    clone = ScanFS::InodeCache.clone
    assert( 1 == clone[@test_inode_1], "Inode cache clone still contains #{@test_inode_1}" )
  end

  def test_collisions
    test_keys = 10_000_000
    (1..test_keys).each { |node|
      assert( !ScanFS::InodeCache.has_node?(node), "Inode value #{node} does not collide" )
    }
  end

end
