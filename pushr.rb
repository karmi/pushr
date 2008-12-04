require 'rubygems'
require 'sinatra'
require 'yaml'
require 'logger'

# = Pushr
# Deploy Rails applications by Github Post-Receive URLs launching Capistrano's commands
# An experiment.

CONFIG = YAML.load_file( File.join(File.dirname(__FILE__), 'config.yml') ) unless defined? CONFIG

# == Pushr class wraps everything
class Pushr

  Struct.new('Repository', :revision, :message, :author, :when, :datetime) unless defined? Struct::Repository

  unless defined? LOGGER
    LOGGER       = Logger.new(File.join(File.dirname(__FILE__), 'deploy.log'), 'weekly')
    LOGGER.level = Logger::INFO
  end

  attr_reader :path, :application, :repository

  def initialize(path)
    log.fatal('Pushr.new') { "Path not valid: #{path}" } and raise ArgumentError, "File not found: #{path}" unless File.exists?(path)
    @path = path
    @application = ::CONFIG['application'] || "You really should set this to something"
    @repository  = repository_info
  end

  def log
    LOGGER
  end

  def deploy!(force=false)
    if uptodate? # Do not deploy if up-to-date (eg. push was to other branch)
      log.info('Pushr') { "No updates for application found" } and return {:success => false, :output => 'Application is uptodate'}
    end unless force
    cap_command = CONFIG['cap_command'] || 'deploy:migrations'
    log.info(application) { "Deployment starting..." }
    cap_output = %x[cd #{path}/shared/cached-copy; cap #{cap_command} 2>&1]
    success    = (cap_output.to_s =~ /fail/).nil?
    # TODO : Refactor logging/notifying into Observers, obviously!
    # ---> Log
    if success
      log.info('[SUCCESS]')   { "Successfuly deployed application with revision #{repository.revision} (#{repository.message}). Capistrano output:" }
      log.info('Capistrano')  { cap_output.to_s }
    else
      log.warn('[FAILURE]')   { "Error when deploying application! Check Capistrano output below:" }
      log.warn('Capistrano')  { cap_output.to_s }
    end
    # ---> Twitter
    if CONFIG['twitter'] && !CONFIG['twitter']['username'].nil? && !CONFIG['twitter']['password'].nil?
      twitter_message = (success) ?
        "Deployed #{application} with revision #{repository.revision} — #{repository.message.slice(0, 100)}" :
        "FAIL! Deploying #{application} failed. Check log for details."
      %x[curl --silent --data status='#{twitter_message}' http://#{CONFIG['twitter']['username']}:#{CONFIG['twitter']['password']}@twitter.com/statuses/update.json]
    end
    # TODO : This still smells
    { :success => success, :output  => cap_output.to_s }
  end

  private

  def repository_info
    info = `cd #{path}/current; git log --pretty=format:'%h --|-- %s --|-- %an --|-- %ar --|-- %ci' -n 1`
    Struct::Repository.new( *info.split(/\s{1}--\|--\s{1}/) )
  end

  def uptodate?
    info = `cd #{path}/current; git fetch -q origin deploy 2>&1`
    log.fatal('git fetch -q origin') { "Error while checking if app up-to-date: #{info}" } and return false unless $?.success?
    log.info('Pushr') { "Fetched new revisions from remote..." }
    return info.strip == '' # Blank output => No updates from git remote
  end

end

# Log into file in production
configure :production do
  sinatra_log = File.new(File.join( File.dirname(__FILE__), 'sinatra.log'), "w")
  STDOUT.reopen(sinatra_log)
  STDERR.reopen(sinatra_log)
end

# Authorize all requests with username/password set in <tt>config.yml</tt>
before do
  throw :halt, [404, "Not configured\n"] and return unless configured?
  headers('WWW-Authenticate' => %(Basic realm="[pushr] #{CONFIG['application']}")) and \
  throw(:halt, [401, "Not authorized\n"]) and \
  return unless authorized?
end

helpers do

  def authorized?
    @auth ||=  Rack::Auth::Basic::Request.new(request.env) { |username, password| username == 'admin' && password == 'secret' }
    @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials.first == CONFIG['username'] && @auth.credentials.last == CONFIG['password']
  end

  def configured?
    CONFIG['username'] && !CONFIG['username'].nil? && CONFIG['password'] && !CONFIG['password'].nil?
  end

end

# == Get info
get '/' do
  @pushr = Pushr.new(CONFIG['path'])
  haml :info
end

# == Deploy!
post '/' do
  @pushr = Pushr.new(CONFIG['path'])
  @info = @pushr.deploy!(params[:force])
  haml :deployed
end

# == Look nice
get '/style.css' do
  content_type 'text/css', :charset => 'utf-8'
  sass :style
end

use_in_file_templates!

__END__

@@ layout
%html
  %head
    %title= "[pushr] #{CONFIG['application']}"
    %meta{ 'http-equiv' => 'Content-Type', :content => 'text/html;charset=utf-8' }
    %link{ :rel => 'stylesheet', :type => 'text/css', :href => "/style.css" }
  %body
    = yield

@@ info
%div.info
  %p
    Last deployed revision of
    %strong
      %em
        = @pushr.application
    is
    %strong
      = @pushr.repository.revision
    \:
    %strong
      %em
        = @pushr.repository.message
    committed
    %strong
      = @pushr.repository.when
    by
    = @pushr.repository.author
  %p
    %form{ :action => "/", :method => 'post', :onsubmit => "this.submit.disabled='true'" }
      %input{ 'type' => 'hidden', 'name' => 'force', 'value' => true }
      %input{ 'type' => 'submit', 'value' => 'Deploy!', 'name' => 'submit', :id => 'submit' }


@@ deployed
- if @info[:success]
  %div.success
    %h2
      Application deployed successfully.
    %form{ 'action' => "", :method => 'get' }
      %p
        %input{ 'type' => 'submit', 'value' => 'Return to index' }
    %pre
      = @info[:output]
- else
  %div.failure
    %h2 There were errors when deploying the application!
    %pre
      = @info[:output]

@@ style
body
  :color #000
  :background #f8f8f8
  :font-size 90%
  :font-family Helvetica, Tahoma, sans-serif
  :line-height 1.5
  :padding 10%
  :text-align center
div
  :border 4px solid #ccc
  :padding 3em
div h2
  :margin-bottom 1em
a
  :color #000
div.success h2
  :color #128B45
div.failure h2
  :color #E21F3A
pre
  :color #444
  :font-size 95%
  :text-align left
  :word-wrap  break-word
  :white-space pre
  :white-space pre-wrap
  :white-space -moz-pre-wrap
  :white-space -o-pre-wrap
