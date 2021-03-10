# Sinatra handlers for the device settings page.
# (C)2012 Mike Bourgeous

class LogicStatusPage < Sinatra::Base
  aget '/settings' do
    @title = 'Nitrogen Logic Controller Settings'
    body erb :settings
  end
end
