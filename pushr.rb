# = Pushr
# Deploy Rails applications by running Capistrano tasks with post-commit hooks
# An experiment. Various notifications? Better logging? Sure. Let's just wait a little bit, shall we? :)

require 'rubygems'
require 'sinatra'
require 'yaml'

CONFIG = YAML.load_file( File.join(File.dirname(__FILE__), 'config.yml') ) unless defined? CONFIG

# == Pushr class
# Just wrapping logic somehow, at the moment
class Pushr
  def info
    revision_info = `cd #{CONFIG['path']}/shared/cached-copy; git log --pretty=format:'%h : %s [%ar by %an]' -n 1`
  end
  def deploy
    cap_output = %x[cd #{CONFIG['path']}/shared/cached-copy; cap deploy:migrations 2>&1]
    { :success => (cap_output.to_s =~ /failed/).nil?,
      :output  => cap_output }
  end
end

# Log into file in production
configure :production do
  log = File.new(File.join( File.dirname(__FILE__), 'pushr.log'), "w")
  STDOUT.reopen(log)
  STDERR.reopen(log)
end

# Authorize all requests with the token set in <tt>config.yml</tt>
before do
  throw :halt, [404, "Not configured\n"] and return if not CONFIG['token'] or CONFIG['token'].nil?
  throw :halt, [500, "You did wrong.\n"] and return unless params[:token] && params[:token] == CONFIG['token']
end

# == Get info
get '/' do
  @info = Pushr.new.info
  haml :info
end

# == Deploy!
post '/' do
  @info = Pushr.new.deploy
  haml :deployed
end

get '/style.css' do
  content_type 'text/css', :charset => 'utf-8'
  sass :style
end

use_in_file_templates!

__END__

@@ layout
%html
  %head
    %title= 'I am Pushr'
    %meta{ 'http-equiv' => 'Content-Type', :content => 'text/html;charset=utf-8' }
    %link{ :rel => 'stylesheet', :type => 'text/css', :href => "/style.css?token=#{CONFIG['token']}" }
  %body
    = yield

@@ info
%div.info
  %p
    Last deployed revision is
    %strong
      = @info
  %p
    %form{ 'action' => "/", :method => 'post' }
      %input{ 'type' => 'hidden', 'name' => 'token', 'value' => CONFIG['token'] }
      %input{ 'type' => 'submit', 'value' => 'Deploy!', 'onclick' => 'this.disable()' }


@@ deployed
- if @info[:success]
  %div.success
    %h2
      Application deployed successfully.
    %form{ 'action' => "", :method => 'get' }
      %input{ 'type' => 'hidden', 'name' => 'token', 'value' => CONFIG['token'] }
      %p
        %input{ 'type' => 'submit', 'value' => 'Return to index' }
    %pre
      = @info[:output]
- else
  %div.failure
    %h2 There were errors when deploying application!
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
  :color green
div.failure h2
  :color red
pre
  :color #444
  :font-size 95%
  :text-align left
  :word-wrap  break-word
  :white-space pre
  :white-space pre-wrap
  :white-space -moz-pre-wrap
  :white-space -o-pre-wrap
