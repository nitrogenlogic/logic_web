#!/usr/bin/env ruby
# Nitrogen Logic Automation Controller logic system status page
# (C)2016 Mike Bourgeous
#
# Useful references:
# http://titusd.co.uk/2010/04/07/a-beginners-sinatra-tutorial

require 'bundler/setup'
require 'rubygems'
require 'sinatra/async'
require 'socket'
require 'dnssd'
require 'json'

require 'nl/logic_client'

$:.unshift(File.expand_path('../lib', __FILE__))
require 'logic_web/version'

if __FILE__ == $0
  exec('rackup -p 4567 -s thin ' + File.join(File.dirname(__FILE__), 'logic_web.ru'))
end

# Prints the given message, prefixed by the current time.
def n2log(msg)
  puts "#{Time.now.strftime('%Y-%m-%d %H:%M:%S.%6N %z')} - #{msg}"
end

# Logs an exception or error message.
def n2log_e(e, msg = nil)
  if e.is_a? Exception
    n2log "\e[1;31m#{msg ? (msg + ' - ') : ''}#{e.inspect}\e[0;31m\n\t#{e.backtrace.join("\n\t")}\e[0m"
  else
    n2log "\e[0;31m#{e}\e[0m"
  end
end

# Implement logging by wrapping some async_sinatra internals.  Logging can be
# disabled for an entire route by passing :no_log (with any value) in the route
# options, or by setting @no_log to a truthy value.  @no_log may also be a
# lambda that returns whether to log a particular request.
module Sinatra::Async
  alias :oldaroute :aroute
  def aroute(verb, path, opts = {}, &block)
    # Based on aroute from async_sinatra

    run_method = :"RunA#{verb} #{path} #{opts.hash}"
    define_method run_method, &block

    no_log = opts.include?(:no_log)
    opts.delete :no_log

    log_method = :"LogA#{verb} #{path} #{opts.hash}"
    define_method(log_method) { |*a|
      @no_log = @no_log.call if @no_log.respond_to? :call
      unless @no_log || no_log
        msg = "#{request.ip} - #{status} #{verb} #{request.path}"
        msg << " [#{path}]" if path != request.path
        n2log msg
      end
    }

    oldaroute verb, path, opts do |*a|
      oldcb = request.env['async.callback']
      request.env['async.callback'] = proc { |*args|
        oldcb[*args]
        async_runner(log_method, *a)
      }

      async_runner(run_method, *a)
    end
  end
end

module Sinatra::Async::Helpers
  if Gem.respond_to? :searcher
    # Rubygems 1.3.7
    version = Gem.searcher.find('async_sinatra').version
  else
    # Rubygems 2.x
    version = Gem::Specification.find_by_name('async_sinatra').version
  end

  if version <= Gem::Version.new('0.5.0')
    # This is a workaround for a bug in async_sinatra 0.5.0
    # Without this, a request that triggers an exception will never
    # have its response sent.
    alias :old_async_exception :async_handle_exception
    def async_handle_exception(*args, &block)
      raised = false

      old_async_exception *args do |*a|
        begin
          yield *a
        rescue ::Exception => e
          n2log_e e, "Exception caught by async_handle_exception"
          if settings.show_exceptions?
            raised = true
            raise
          else
            @title = 'Internal server error'
            body erb box('An internal error occurred.  Please contact your support representative.', @title)
          end
        end
      end

      if raised
        env['async.callback'] [[response.status, response.headers, response.body]]
      end
    end
  end
end

# For running a subset of commands via sudo.  Only authorized commands set to
# NOPASSWD in /etc/sudoers will work.  Will only run sudo if it exists in
# /usr/bin/sudo or /bin/sudo.  Uses EventMachine::system().
#
# TODO: Share with KNC?
module Sudo
  @@sudo_cmd = if File.executable?('/usr/bin/sudo')
    '/usr/bin/sudo -S -n -- '
  elsif File.executable?('/bin/sudo')
    '/bin/sudo -S -n -- '
  else
    # TODO: Use a logging method that automatically adds timestamps
    n2log_e "#{Time.now} - sudo command not found -- some tasks may not work"
    ''
  end

  # Passes the complete command_line to sudo, like this: "sudo -n -- [command_line]".  The
  # block will be passed to EM.system as well.
  def self.sudo(command_line, &block)
    n2log "SUDO: Calling sudo: #{@@sudo_cmd}#{command_line}"
    EM.system('/bin/sh', '-c', "#{@@sudo_cmd}#{command_line}") do |*a|
      block.call(*a)
    end
  end
end

class LogicStatusPage < Sinatra::Base
end

# FIXME: This class/require/class combo is needed so that Sinatra doesn't think
# that 'lib/' is our top-level directory.  TODO: move all the netdevices
# methods into a different module and use qualified names.
require 'netdevices'

class LogicStatusPage < Sinatra::Base
  register Sinatra::Async

  def self.get_or_post(path, opts={}, &block)
    get path, opts, &block
    post path, opts, &block
  end

  def self.aget_or_post(path, opts={}, &block)
    aget path, opts, &block
    apost path, opts, &block
  end

  configure do
    set :public_folder => File.dirname(__FILE__) + '/static'
    $lsrv=ENV["LOGIC_HOST"] || 'localhost'
    LogicStatusPage.start_network_browser
  end

  configure :development do
    Thread.abort_on_exception = true
    enable :raise_exceptions
  end

  configure :production do
    enable :logging
  end

  helpers do
    include Rack::Utils

    alias :h :escape_html;

    # Returns the current @title, or a default title if @title is nil.
    def get_title
      @title || "Nitrogen Logic Controller Status"
    end

    # Returns a string containing an error page
    def error_page(header = 'Error', message = 'An error occurred.', http_status = nil)
      content_type 'text/html', :charset => 'utf-8'
      status(http_status || 500) if status == 200 or http_status
      @title = "Error - #{get_title}"
      erb :error, :locals => {:header => header || '', :message => message || ''}
    end

    # Sets an error_page-calling errback on a Logic System Command object
    def check(cmd)
      cmd.errback { |c|
        body error_page 'Error processing command', c ? c.message : ''
      }
    end

    # Returns a string containing a backend connection error page
    def connect_error
      error_page 'Error connecting', 'An error occurred while connecting to the logic backend.'
    end

    # Wraps content in a light-colored box.  If header is an array,
    # the first element will be HTML escaped and placed in the
    # primary header.  The second element will be used as a
    # secondary header without HTML escaping.
    def box_light(content = '', header = nil, classes = nil, tag = 'section')
      # TODO: If allowing any user content in here, prevent
      # injection of unwanted text
      @boxcontent = content || ''
      if header.is_a? Array
        @boxheader = h header[0]
        @boxright = header[1]
      else
        @boxheader = h header
        @boxright = nil
      end
      @boxclasses = (classes && classes.respond_to?(:join)) ? classes.join(' ') : classes
      @boxtag = tag || 'section'
      erb :_box, :layout => false
    end

    # Wraps content in a dark-colored box
    def box(content = '', header = nil, classes = nil, tag = 'section')
      # TODO: If allowing any user content in here, prevent
      # injection of unwanted text
      classes = classes || [];
      classes = ['darkbox', 'invbox', *Array(classes)];

      box_light content, header, classes, tag
    end

    # Does a rough conversion of raw text to html.
    def t2h(text)
      # TODO: Use markdown or some other template engine?
      escape_html(text).gsub(/\r?\n(.)/, "<br>\n\\1").gsub("\t", '&nbsp;&nbsp;&nbsp;&nbsp;');
    end

    # Gets a connection to the logic server and executes the block with it.
    # Returns an error page to the client in the event of an error.
    def logic(&block)
      NL::LC.get_connection($lsrv, proc { yield nil }) do |c|
        yield c
      end
    rescue EventMachine::ConnectionError => e
      n2log_e e, "ConnectionError while connecting to logic backend"
      yield nil
    end

    # Gets exports from the given logic_connection (obtained via
    # the logic() helper above), then sends them to the client as
    # JSON.
    def send_exports(logic_connection)
      cmd = logic_connection.get_exports { |exports|
        content_type 'application/json', :charset => 'utf-8'
        response.headers['Cache-Control'] = 'no-cache'
        response.headers['Pragma'] = 'no-cache'
        body exports.map {|ex| ex.to_h}.to_json
      }
      cmd.errback { |c|
        content_type 'text/plain', :charset => 'utf-8'
        status 422
        text = 'Error getting exports from the backend'
        text << (c ? ": #{c.message}" : '.')
        body text
      }
    end
  end

  aget '/' do
    logic do |c|
      if c.nil?
        @exports = []
        @design = {
          'name' => 'No design is running.',
          'revision' => [0, 0],
          'numobjs' => 0,
          'avg' => Float::INFINITY,
          'period' => Float::INFINITY,
        }
        body erb(:index)
      else
        cmd = c.get_exports do |list|
          cmd2 = c.get_info do |info|
            @exports = list
            @design = info
            body erb(:index)
          end
          cmd2.errback { body error_page 'Error getting logic design info' }
        end
        cmd.errback { body error_page 'Error getting list of exports' }
      end
    end

    # TODO: When rendering a view, allow partials to add a stylesheet to the CSS
    # links in <head> by inserting the path name of the stylesheet relative to the
    # application (e.g. <% @styles << '/css/exports.css' %>)

    # TODO: Allow automatic dynamic replacement of an individual partial view via
    # AJAX.  Wrap the partial in an unstyled div or span (use a tag parameter to a
    # partial() helper method to specify any container, similar to box() -- set
    # class="partial", data-partial="[name_of_partial]" on the container), then use
    # JavaScript to set the innerHTML of the tag to the new content of the partial.
    # Allow specifying update interval (in some granularity to allow grouping of
    # requests).  Maybe serve the content of multiple partials in a single JSON
    # return.  Also make it possible to have form "submission" replace a partial
    # (use JavaScript to submit the form instead, or use an iframe).
  end

  not_found do
    # FIXME: This doesn't work in production mode
    status 404
    n2log "#{request.ip} - #{status} #{request.request_method} #{request.url}"
    @title = '404 - Not Found'
    erb :notfound
  end
end

# Calls require on each file in the given directory that ends with '.rb'.  Does
# not recurse into subdirectories.
def require_dir(dir)
  Dir.foreach(File.expand_path(dir)) do |file|
    if file.end_with? '.rb'
      path = File.join(dir, file)
      puts "Loading #{path}"
      require path
    end
  end
end

require_dir './routes/'
