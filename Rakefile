require 'rake'

CONFIG = YAML.load_file( File.join(File.dirname(__FILE__), 'config.yml') ) unless defined? CONFIG

task :default => 'app:start'

namespace :app do

  task :start do
    system "ruby pushr.rb -p 4000"
  end

end