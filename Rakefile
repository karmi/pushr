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
  desc "Add public key for the user@server to 'itself' (so Cap can SSH to localhost)"
  task :add_public_key_to_localhost do
    # TODO : Ask for key name with Highline
    `cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys`
  end
end

namespace :start do

  desc "Start application in development mode"
  task :development do
    system "ruby pushr.rb -p 4000"
  end

  desc "Start application in production mode"
  task :production do
    port = ENV['PORT'] || 4000
    puts "Starting Pushr on port #{port}..."
    system "nohup ruby pushr.rb -p #{port} -e production &"
  end

end
