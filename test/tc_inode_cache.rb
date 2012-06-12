#!/usr/bin/env ruby

$:.unshift File.dirname(__FILE__)
require 'helper'

class TC_TestInodeCache < Test::Unit::TestCase

  def setup
    ScanFS::InodeCache.init
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
    clone = ScanFS::InodeCache.clone(@test_inode_1)
    assert( clone.include?(@test_inode_1), "Inode cache clone still contains #{@test_inode_1}" )
  end

  def test_collisions
    collisions = 0
    test_keys = 1_000_000
    (1..test_keys).each { |node|
      collisions += 1 if ScanFS::InodeCache.has_node?(node)
    }
    collision_pct = collisions.to_f/test_keys*100
    assert( collision_pct < 0.05, "Inode cache exhibits less than 0.05% collision over #{test_keys} entries" )
    puts "Collision percentage: %.4f%%" % collision_pct
  end

end
