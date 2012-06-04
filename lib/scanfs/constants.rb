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

end # module ScanFS::Constants
