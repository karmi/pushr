require 'rake'
require 'yaml'

CONFIG = YAML.load_file( File.join(File.dirname(__FILE__), 'config.yml') ) unless defined? CONFIG

task :default => 'start:development'

namespace :app do
  desc "Check dependencies of the application"
  task :check do
    begin
      require 'rubygems'
      require 'sinatra'
      require 'haml'
      require 'sass'
      require 'capistrano'
      puts "\n[*] Good! You seem to have all the neccessary gems for Pushr"
    rescue LoadError => e
      puts "[!] Bad! Some gems for Pusher are missing!"
      puts e.message
    ensure
      Sinatra::Application.default_options.merge!(:run => false)
    end
    
  end
end

namespace :start do

  desc "Start application in development mode"
  task :development do
    system "ruby pushr.rb -p 4000"
  end

  desc "Start application in production mode"
  task :production do
    system "nohup ruby pushr.rb -p 4000 -e production &"
  end

end
