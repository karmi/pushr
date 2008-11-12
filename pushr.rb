# = Pushr
# Deploy Rails applications by running Capistrano tasks with post-commit hooks
# An experiment. Very probably will be more sophisticated .)

require 'rubygems'
require 'sinatra'
require 'yaml'

CONFIG = YAML.load_file( File.join(File.dirname(__FILE__), 'config.yml') ) unless defined? CONFIG

class Pushr
  def info
    revision_info = `cd #{CONFIG['path']}/shared/cached-copy; git log --pretty=format:'%h : %s [%ar by %an]' -n 1`
    "Last deployed revision is #{revision_info}"
  end
  def deploy
    deploy_info = `cd #{CONFIG['path']}/shared/cached-copy; cap deploy:migrations`
    deploy_info
  end
end

# Authorize all requests with the token set in <tt>config.yml</tt>
before do
  throw :halt, [404, "Not configured\n"] and return if not CONFIG['token'] or CONFIG['token'].nil?
  throw :halt, [500, "You did wrong.\n"] and return unless params[:token] && params[:token] == CONFIG['token']
end

get '/' do
  Pushr.new.info
end

post '/' do
  Pushr.new.deploy
end
