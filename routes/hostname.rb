# Sinatra handlers for changing the device's hostname.
# (C)2012 Mike Bourgeous

class LogicStatusPage < Sinatra::Base
  aget '/hostname' do
    status 302
    response.headers['Location'] = '/settings' # FIXME: needs an absolute URI
    ahalt
  end

  apost '/hostname' do
    # TODO: Check referrer, session, and CSRF (use middleware or
    # filter to require authentication based on path?)
    @title = "Set Hostname"
    host = params[:hostname].strip.downcase
    if host =~ /[^[:alnum:]-]/
      body error_page 'Invalid hostname', "&ldquo;#{t2h host}&rdquo; is not a valid hostname."
    else
      Sudo.sudo("/opt/nitrogenlogic/util/set_hostname.sh #{host} 2>&1") do |text, status|
        if status.success?
          link = %Q{<p><a href="//#{host}.local:4567/settings">Click here to go to the new hostname.</a></p>}
          body erb box("<p>Hostname set to #{h host}.local: #{t2h text.strip}</p> #{link}",
                       'Successfully set hostname', 'fullbox')
        else
          # TODO: Distinguish between invalid hostname (400) and other error (500)
          # TODO: 400 should only be used for HTTP syntax errors
          body error_page 'Error setting hostname', text, 400
        end
      end
    end
  end
end
