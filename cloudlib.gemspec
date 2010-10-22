Gem::Specification.new do |s|
  s.name     = "cloudlib"
  s.version  = "0.3.10"
  s.date     = "2010-10-21"
  s.summary  = "Tools for maintaining a library of books and articles in Amazon S3 and SimpleDB"
  s.email    = "jgm@berkeley.edu"
  s.homepage = "http://github.com/jgm/cloudlib"
  s.description = "Cloudlib is a ruby library and commands for maintaining a library of books and articles on the Amazon 'cloud': S3 and SimpleDB."
  s.has_rdoc = true
  s.authors  = ["John MacFarlane"]
  s.bindir   = "bin"
  s.executables = ["cloudlib", "cloudlib-web"]
  s.default_executable = "cloudlib"
  s.files    = [ "README",
        "LICENSE",
        "cloudlib.gemspec", 
        "lib/cloudlib.rb",
        "bin/cloudlib",
        "bin/cloudlib-web" ]
  s.test_files = []
  s.rdoc_options = ["--main", "README", "--inline-source"]
  s.extra_rdoc_files = ["README"]
  s.add_dependency("aws-s3", [">= 0.5.1"])
  s.add_dependency("aws-sdb", [">= 0.3.1"])
  s.add_dependency("sinatra", [">= 0.3.2"])
  s.add_dependency("highline", [">= 1.2.9"])
end

