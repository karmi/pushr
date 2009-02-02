require 'rubygems'
require 'sinatra'
require 'yaml'
require 'logger'

# = Pushr
# Deploy Rails applications by Github Post-Receive URLs launching Capistrano's commands

CONFIG = YAML.load_file( File.join(File.dirname(__FILE__), 'config.yml') ) unless defined? CONFIG

class String
  # http://github.com/rails/rails/blob/master/activesupport/lib/active_support/core_ext/string/inflections.rb#L44-49
  def camelize
    self.gsub(/\/(.?)/) { "::#{$1.upcase}" }.gsub(/(?:^|_)(.)/) { $1.upcase }
  end
end

module Pushr

  # == Shared logger
  module Logger
    unless defined? LOGGER
      LOGGER       = ::Logger.new(File.join(File.dirname(__FILE__), 'deploy.log'), 'weekly')
      LOGGER.level = ::Logger::INFO
    end
    def log; LOGGER; end
  end

  # == Wrapping notifications
  # Inspired by http://github.com/foca/integrity
  class Notifier

    # Inherit from this class in your notifiers
    # See eg. http://github.com/karmi/pushr_notifiers/blob/master/irc.rb
    class Base

      include Pushr::Logger

      attr_reader :config

      def initialize(config={})
        @config = config
        log.fatal("#{self.class.name}") { "Notifier not configured!" } unless configured?
      end

      # Implement this method for your particular notification method
      def deliver!
        raise NoMethodError, "You need to implement 'deliver!' method in your notifier"
      end

      private

      # Over-ride this method to send diferent message
      def message(notification)
        if notification.success
          "Deployed #{notification.application} with revision #{notification.repository.info.revision} — #{notification.repository.info.message.slice(0, 100)}"
        else
          "FAIL! Deploying #{notification.application} failed. Check deploy.log for details."
        end
      end

      # Implement this method to check for notifier configuration
      def configured?
        raise NoMethodError, "You need to implement 'configured?' method in your notifier"
      end

    end

    # Twitter notifications (default)
    class Twitter < Base

      def deliver!(notification)
        return unless configured?
        %x[curl --silent --data status='#{message(notification)}' http://#{config['username']}:#{config['password']}@twitter.com/statuses/update.json]
      end

      private

      def configured?
        !config['username'].nil? && !config['password'].nil?
      end
    end

  end # end Notifier

  # == Wrapping Git stuff
  class Repository

    include Logger

    Struct.new('Info', :revision, :message, :author, :when, :datetime) unless defined? Struct::Info

    def initialize(path)
      @path = path
    end

    def info
      info = `cd #{@path}/current; git log --pretty=format:'%h --|-- %s --|-- %an --|-- %ar --|-- %ci' -n 1`
      @info ||= Struct::Info.new( *info.split(/\s{1}--\|--\s{1}/) )
    end

    def reload!
      @info = nil
      info
    end

    def uptodate?
      log.info('Pushr') { "Fetching new revisions from remote..." }
      info = `cd #{@path}/shared/cached-copy; git fetch -q origin 2>&1`
      log.fatal('git fetch -q origin') { "Error while checking if app up-to-date: #{info}" } and return false unless $?.success?
      return info.strip == '' # Blank output => No updates from git remote
    end

  end # end Repository

  # == Wrapping application logic
  class Application

    include Logger

    attr_reader :path, :application, :repository, :success, :cap_output

    def initialize(path)
      log.fatal('Pushr.new') { "Path not valid: #{path}" } and raise ArgumentError, "File not found: #{path}" unless File.exists?(path)
      @path = path
      @application = ::CONFIG['application'] || "You really should set this to something"
      @repository  = Repository.new(path)
      load_notifiers
    end

    def deploy!(force=false)
      if repository.uptodate? # Do not deploy if up-to-date (eg. push was to other branch) ...
        log.info('Pushr') { "No updates for application found" } and return {:@success => false, :output => 'Application is uptodate'}
      end unless force == 'true' # ... unless forced from web GUI
      cap_command = CONFIG['cap_command'] || 'deploy:migrations'
      log.info(application) { "Deployment #{"(force) " if force == 'true' }starting..." }
      @cap_output  = %x[cd #{path}/shared/cached-copy; cap #{cap_command} 2>&1]
      @success     = $?.success?
      @repository.reload!  # Update repository info (after deploy)
      log_deploy_result
      send_notifications
    end

    private

    def log_deploy_result
      if @success
        log.info('[SUCCESS]')   { "Successfuly deployed application with revision #{repository.info.revision} (#{repository.info.message}). Capistrano output:" }
        log.info('Capistrano')  { @cap_output.to_s }
      else
        log.warn('[FAILURE]')   { "Error when deploying application! Check Capistrano output below:" }
        log.warn('Capistrano')  { @cap_output.to_s }
      end
    end

    def load_notifiers
      @notifiers_path = CONFIG['notifiers_path'] || '../pushr_notifiers'
      @notifiers = []
      CONFIG['notifiers'].each do |notifier|
        notifier_name, notifier_config = notifier.to_a.flatten
        unless Pushr::Notifier::const_defined?(notifier_name.to_s.camelize)
          begin
            require File.join( File.dirname(__FILE__), @notifiers_path, notifier_name  ) 
          rescue Exception => e
            raise LoadError, "Notifier #{notifier_name} not found! (#{e.message})"
          end
        end
        @notifiers << Pushr::Notifier::const_get( notifier_name.to_s.camelize ).new(notifier_config)
      end
    end

    def send_notifications
      @notifiers.each { |n| n.deliver!(self) }
    end

  end # end Application

end # end Pushr

# -------  Sinatra gets on stage here  --------------------------------------------------

# -- Authorize all requests with username/password set in <tt>config.yml</tt>
before do
  halt [404, "Not configured\n"] and return unless configured?
  response['WWW-Authenticate'] = %(Basic realm="[pushr] #{CONFIG['application']}") and \
  halt([401, "Not authorized\n"]) and \
  return unless authorized?
end

# -- Helpers
helpers do

  def authorized?
    @auth ||=  Rack::Auth::Basic::Request.new(request.env)
    @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials.first == CONFIG['username'] && @auth.credentials.last == CONFIG['password']
  end

  def configured?
    CONFIG['username'] && !CONFIG['username'].nil? && CONFIG['password'] && !CONFIG['password'].nil?
  end

end

# == Get info
get '/' do
  @pushr = Pushr::Application.new(CONFIG['path'])
  haml :info
end

# == Deploy!
post '/' do
  @pushr = Pushr::Application.new(CONFIG['path'])
  @pushr.deploy!(params[:force])
  haml :deployed
end

# == Look nice
get '/style.css' do
  content_type 'text/css', :charset => 'utf-8'
  sass :style
end
get( '/favicon.ico' ) { content_type 'image/gif' }

__END__

@@ layout
%html
  %head
    %title= "[pushr] #{@pushr.application}"
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
      = @pushr.repository.info.revision
    \:
    %strong
      %em
        = @pushr.repository.info.message
    committed
    %strong
      = @pushr.repository.info.when
    by
    = @pushr.repository.info.author
  %p
    %form{ :action => "/", :method => 'post', :onsubmit => "this.submit.disabled='true'" }
      %input{ 'type' => 'hidden', 'name' => 'force', 'value' => 'true' }
      %input{ 'type' => 'submit', 'value' => 'Deploy!', 'name' => 'submit', :id => 'submit' }


@@ deployed
- if @pushr.success
  %div.success
    %h2
      Application deployed successfully.
    %form{ 'action' => "", :method => 'get' }
      %p
        %input{ 'type' => 'submit', 'value' => 'Return to index' }
    %pre
      = @pushr.cap_output
- else
  %div.failure
    %h2
      There were errors when deploying the application!
    %form{ 'action' => "", :method => 'get' }
      %p
        %input{ 'type' => 'submit', 'value' => 'Return to index' }
    %pre
      = @pushr.cap_output

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
