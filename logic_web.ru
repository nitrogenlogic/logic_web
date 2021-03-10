require_relative 'logic_web'

run Rack::URLMap.new '/' => LogicStatusPage.new
