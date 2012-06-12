require 'rubygems'
require 'digest/md5'

class BitField

  attr_reader :buckets

  def initialize(opts={})
    @bits = opts.fetch(:bits, 255)
    @bucketsize = opts.fetch(:bucketsize, 31)
    @buckets = opts.fetch(:buckets, Array.new((@bits / @bucketsize), 0))
  end

  def setbit (bit)
    b = bit % @bucketsize
    @buckets[(bit / @bucketsize)] |= (1 << b)
  end

  def bitset? (bit)
    b = bit % @bucketsize
    return (@buckets[(bit / @bucketsize)] & (1 << b) == 0) ? false : true
  end

end # class BitField


class BloomFilter

  attr_accessor :bitfield

  def initialize(opts={})
    throw 'Missing salts key' unless opts[:salts]
    @salts = opts[:salts]
    @bits = opts.fetch(:bits, 255)
    @bucketsize = opts.fetch(:bucketsize, 31)

    bf_opts = { :bits => @bits, :bucketsize => @bucketsize }
    bf_opts[:buckets] = opts[:buckets] unless opts[:buckets].nil?
    @bitfield = BitField.new(bf_opts)
  end

  def clone
    BloomFilter.new(
      :salts => @salts,
      :bits=> @bits,
      :bucketsize => @bucketsize,
      :buckets => @bitfield.buckets.dup
    )
  end

  def hashes(v)
    r = []
    @salts.each { |salt|
      r.push(
        Digest::MD5.hexdigest("#{salt}#{v}")[0..7].to_i(16) % @bits
      )
    }
    return r
  end

  def add(v)
    self.hashes(v).each { |bit| @bitfield.setbit(bit) }
  end

  def include?(v)
    self.hashes(v).each { |bit|
      next if @bitfield.bitset?(bit)
      return false
    }
    return true
  end

end # class BloomFilter
