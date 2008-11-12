require 'rake'
require 'yaml'

CONFIG = YAML.load_file( File.join(File.dirname(__FILE__), 'config.yml') ) unless defined? CONFIG

task :default => 'start:development'

namespace :start do

  task :development do
    system "ruby pushr.rb -p 4000"
  end

  task :production do
    system "nohup ruby pushr.rb -p 4000 -e production &"
  end

end