# Sinatra handlers for firmware updates.
# (C)2012 Mike Bourgeous

# Reference: http://stackoverflow.com/questions/4964828/stream-multiple-body-using-async-sinatra
class FirmwareStream < EM::Connection
  include EventMachine::Deferrable
  include Rack::Utils

  def initialize footer
    @footer = footer
  end

  def receive_data data
    chunk escape_html(data)
  end

  def unbind
    result = get_status.exitstatus != 0 ? 'failed' : 'succeeded'

    chunk "</code></pre>"
    chunk <<-EOF
      <h3 class="firmware_result">Firmware update #{result}</h3>
      <script type="text/javascript">
        $('.firmware_output header h2').first().html('<span class="firmware_#{result}">Update #{result}</span>');
        window.onbeforeunload = null;
      </script>
    EOF
    chunk @footer

    get_status.exitstatus != 0 ? fail(result) : succeed(result)
  end

  # Sends a chunk of data to the client.
  def chunk data
    @block.call data.to_s
  end

  # Called by Sinatra with a block used to send data to the client.
  def each &block
    @block = block
  end
end

class LogicStatusPage < Sinatra::Base
  @@firmware_active = false

  aget '/firmware' do
    status 302
    response.headers['Location'] = '/settings'
    ahalt
  end

  apost '/firmware' do
    @title = 'Firmware Update'
    if !(params[:firmware_file] &&
        params[:firmware_file].is_a?(Hash) &&
        (tempfile = params[:firmware_file][:tempfile]) &&
        (filename = params[:firmware_file][:filename]))

      body error_page 'No firmware file found',
        'No firmware file was found in the request.  Please go back, ' <<
      'select a firmware update file, and try again.',
        400
    elsif @@firmware_active
      body error_page 'Firmware update in progress',
        'A firmware update is already in progress.  Please wait for the current firmware update to complete.'
    else
      @@firmware_active = true

      safename = filename.gsub(/[^[:print:]]+/, '')

      n2log "Beginning firmware update: #{safename}."

      # box() escapes the first header.  An HTML-escaped firmware filename can never contain &&&SPLIT&&&.
      header, footer = erb(box("&&&SPLIT&&&", ["Applying #{filename}", "Do not leave this page until the update is complete."], 'firmware_output')).split('&&&SPLIT&&&', 2)

      tempfile.chmod 0400

      fwstream = EM.popen("bash -c 'do_firmware #{tempfile.path} 2>&1 | grep --line-buffered -iv \"cat: write error: Broken pipe\"; exit ${PIPESTATUS[0]}'", FirmwareStream, footer)

      body fwstream
      fwstream.chunk header
      fwstream.chunk <<-EOF
        <script type="text/javascript">
           window.onbeforeunload = function() {
               return "Please wait for the firmware update to finish.";
           }
        </script>
      EOF
      fwstream.chunk "<pre><code>"

      cb = proc { |*result|
        # FIXME: Navigating away from the update page calls this callback,
        # resulting in a firmware update continuing in the background with
        # @@firmware_active set to false.
        tempfile.unlink
        @@firmware_active = false
        n2log "Firmware update #{result.join}: #{safename}."
      }

      fwstream.callback &cb
      fwstream.errback &cb
    end
  end

  aget '/fwstream_test' do
    fw = FirmwareStream.new
    content_type 'text/plain', :charset => 'utf-8'
    body fw
    EM.next_tick do
      c = 0
      timer = EM.add_periodic_timer(0.1) do
        c += 1
        fw.chunk "#{c}\n"
        if c == 50
          timer.cancel
          fw.succeed
        end
      end
    end
  end

  aget '/firmware_test' do
    @title = 'Firmware Templating Test'
    fw = FirmwareStream.new
    body fw
    EM.next_tick do
      text = erb '##### MIDDLE #####'
      header, footer = text.split('##### MIDDLE #####', 2)
      fw.chunk header
      EM.add_timer(5) do
        fw.chunk 'A line of text'
      end
      EM.add_timer(15) do
        fw.chunk footer
        fw.succeed
      end
    end
  end
end
