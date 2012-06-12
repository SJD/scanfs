# -*- encoding: binary -*-

module ScanFS::Constants


  ENGINE = ( (defined?(RUBY_ENGINE)) ? RUBY_ENGINE : 'unknown' )

  USER_DIR = File.join(
    (
      (defined?(ENV['HOME']) && !["", nil].include?(ENV['HOME']))?
        ENV['HOME'] : Dir.home rescue NoMethodError; File.expand_path('~/')
    ),
    '.scanfs'
  )

  CLAMP_MAX_LEEWAY = 24*60*60

  INODE_CACHE_MAX_FILTERS = 64
  INODE_CACHE_BITWIDTH = 0xffffff
  INODE_CACHE_SALTS = ('a'..'z').to_a+('A'..'Z').to_a+(0..9).to_a+['.', '/']

end # module ScanFS::Constants
