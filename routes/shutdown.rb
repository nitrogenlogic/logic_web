# Sinatra handlers for device shutdown.
# (C)2012 Mike Bourgeous

class LogicStatusPage < Sinatra::Base
  aget '/shutdown' do
    @title = "Prepare for Transport"
    body erb :shutdown_prompt
  end

  apost '/shutdown' do
    @title = "Shutting Down"
    Sudo.sudo("/opt/nitrogenlogic/util/shutdown.sh 2>&1") do |text, status|
      if status.success?
        body erb :shutdown_done
      else
        body error_page 'Error shutting down', text, 500
      end
    end
  end
end
