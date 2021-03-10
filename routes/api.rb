# Sinatra handlers for the logic status page API under /api/.
# (C)2012 Mike Bourgeous

class LogicStatusPage < Sinatra::Base
  aget '/api/apitest' do
    content_type 'text/plain', :charset => 'utf-8'
    body "I'm here!"
  end

  aget '/api/get/:obj/:idx' do |obj, idx|
    content_type 'text/plain', :charset => 'utf-8'
    logic do |c|
      if c.nil?
        status 503
        body "ERR - No connection to logic backend - no design running?"
      else
        c.get(obj, idx) { |val|
          # TODO: Return the type somehow?  Support JSON via URL parameter?
          body "#{val}"
        }.errback { |cmd|
          status 422
          body "ERR - #{cmd.message}"
        }
      end
    end
  end

  # TODO: Only accept POST for modifications, add authentication
  aget_or_post '/api/set' do
    content_type 'text/plain', :charset => 'utf-8'
    # TODO: Create+check CSRF token

    # TODO: Use array form parameters (e.g. objid[], value[]) instead?
    multi = []
    regex = /^param_(\d+)_(\d+)$/
    params.each do |k, v|
      k.to_s.scan(regex) do |match|
        multi << {
          :objid => match[0].to_i,
          :index => match[1].to_i,
          :value => v
        }
      end
    end

    # TODO: Wrap get_connection+some_command into individual calls [create a
    # LS::Wrapper class that manages connections to a particular host?  cache
    # values?]
    logic do |c|
      if c.nil?
        status 503
        body 'No connection to logic backend - no design running?'
      else
        c.set_multi(multi) { |count, result|
          if count != result.length
            status 424

            text = ''
            text << "Set #{count} of #{result.length} value(s).\n"
            result.each do |v|
              text << "Set of obj ID #{v[:objid]}, parameter #{v[:index]} to "
              text << "#{v[:value]}: #{v[:result] ? 'success' : 'error'} - "
              text << "#{v[:command].message}\n"
            end

            body text
          elsif back != nil && uri(back) != uri(request.url) && params['redir'] != '0'
            status 302
            response.headers['Location'] = uri(back)
            ahalt
          else
            send_exports c
          end
        }
      end
    end
  end

  aget '/api/exports' do
    @no_log = lambda { status == 200 }
    logic do |c|
      if c.nil?
        status 503
        content_type 'text/plain', :charset => 'utf-8'
        body 'No connection to the logic backend - no design running?'
      else
        send_exports c
      end
    end
  end

  aget '/api/connect_test' do
    @title = 'Connection Test'
    logic do |client|
      if client.nil?
        status 503
        body error_page 'No connection to the logic backend', 'Is there a design running?'
      else
        cmd = client.get_info do |i|
          msg = "<dl>"
          i.each do |k, v|
            msg << "<dt>#{h k}</dt><dd>#{h v}</dd>"
          end
          msg << '</dl>'
          body erb box msg, 'Test command completed successfully'
        end
        cmd.errback do |c|
          body error_page cmd.message
        end
      end
    end
  end
end
