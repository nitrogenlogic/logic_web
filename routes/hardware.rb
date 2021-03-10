# Sinatra handlers for actions related to attached hardware.
# (C)2012 Mike Bourgeous

require 'hw_monitor_client'

class LogicStatusPage < Sinatra::Base
  @@hw_monitor = nil

  helpers do
    # Opens a connection to hw_monitor if one does not already
    # exist.  Calls the given block with the HwClient object 200ms
    # after opening the connection if the connection was just
    # opened.  Calls the given block immediately if the connection
    # was opened previously.  Returns the HwClient object.
    def get_hw_monitor &block
      if @@hw_monitor.nil?
        @@hw_monitor = HwMonitorClient.start
        @@hw_monitor.add_listener { |event, source|
          @@hw_monitor = source if event == :bind
        }
        EM.add_timer(0.2) { yield @@hw_monitor } if block_given?
      else
        yield @@hw_monitor if block_given?
      end
      @@hw_monitor
    end
  end

  aget '/hardware' do
    status 302
    response.headers['Location'] = '/hw'
    ahalt
  end

  aget '/hw' do
    @title = 'Attached Hardware'
    body erb :hardware
  end

  aget '/hw/template' do
    pid = EM.system(%q{bash -c 'make_hw_template | grep -Eiv "^[a-z0-9]+.[ch](c|pp)?:[0-9]+:" | grep -Ev "^ *[0-9a-f]+:?"; exit ${PIPESTATUS[0]}'}) do |output, status|
      if status.success?
        content_type 'application/x-palace', :charset => 'utf-8'
        response.headers['Content-Disposition'] = %Q{attachment; filename="#{Socket.gethostname}.local #{Time.now.strftime('%Y-%m-%d-%H-%M-%S')}.palace"}
        body output
      else
        msg = 'An error occurred while generating the Palace Designer template.'
        Process.kill('KILL', pid) unless status.exited?
        body error_page 'Template generation failed', "#{msg}<pre><code>#{h output}</code></pre>"
      end
    end
  end

  aget '/hw/tree' do
    content_type 'application/json', :charset => 'utf-8'
    get_hw_monitor do |monitor|
      body monitor.to_json
    end
  end
end
