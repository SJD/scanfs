#        NAME: BloominSimple
#      AUTHOR: Peter Cooper
#     LICENSE: MIT ( http://www.opensource.org/licenses/mit-license.php )
#   COPYRIGHT: (c) 2007 Peter Cooper
# DESCRIPTION: Very basic, pure Ruby Bloom filter. Uses my BitField, pure Ruby
#              bit field library (http://snippets.dzone.com/posts/show/4234).
#              Supports custom hashing (default is 3).
#
#              Create a Bloom filter that uses default hashing with 1Mbit wide bitfield
#                bf = BloominSimple.new(1_000_000)
#
#              Add items to it
#                File.open('/usr/share/dict/words').each { |a| bf.add(a) }
#
#              Check for existence of items in the filter
#                bf.includes?("people")     # => true
#                bf.includes?("kwyjibo")    # => false
#
#              Add better hashing (c'est easy!)
#                require 'digest/sha1'
#                b = BloominSimple.new(1_000_000) do |item|
#                  Digest::SHA1.digest(item.downcase.strip).unpack("VVVV")
#                end
#
#              More
#                %w{wonderful ball stereo jester flag shshshshsh nooooooo newyorkcity}.each do |a|
#                  puts "#{sprintf("%15s", a)}: #{b.includes?(a)}"
#                end
#
#                 #  =>   wonderful: true
#                 #  =>        ball: true
#                 #  =>      stereo: true
#                 #  =>      jester: true
#                 #  =>        flag: true
#                 #  =>  shshshshsh: false
#                 #  =>    nooooooo: false
#                 #  => newyorkcity: false

require 'benchmark'
require 'scanfs/ext/bitfield'

class BloominSimple
  attr_reader :bitfield, :hasher

  def initialize(bitsize, bitfield=nil, &block)
    @bitfield = bitfield || BitField.new(bitsize)
    @size = bitsize
    @hasher = block || lambda do |word|
      #word = word.downcase.strip
      [h1 = word.to_s.sum, h2 = word.hash, h2 + h1 ** 3]
    end
  end

  def clone
    BloominSimple.new(@size, @bitfield.clone)
  end

  def add(item)
    @hasher[item].each { |hi| @bitfield[hi % @size] = 1 }
  end

  def includes?(item)
    @hasher[item].each { |hi| return false unless @bitfield[hi % @size] == 1 } and true
  end
end
