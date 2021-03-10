# Methods for querying network devices using Avahi/DNS-SD.
# (C)2012 Mike Bourgeous

require 'timeout'

class LogicStatusPage < Sinatra::Base
  @@network_devices = {}
  @@avahi_mutex = Mutex.new
  def self.network_devices replacement = nil
    @@avahi_mutex.synchronize do
      @@network_devices = replacement if replacement
      @@network_devices
    end
  end

  def self.add_device service_name, device_hash
    @@avahi_mutex.synchronize do
      n2log "Adding device #{device_hash[:name]} at #{device_hash[:ip]}" unless @@network_devices.has_key? service_name
      @@network_devices[service_name] = device_hash
    end
  end

  def self.remove_device service_name
    @@avahi_mutex.synchronize do
      device_hash = @@network_devices.delete(service_name)
      n2log "Removing device #{device_hash[:name]}" if device_hash
    end
  end

  def self.start_network_browser
    @@avahi_mutex.synchronize do
      @@network_devices.clear
    end

    t = Thread.new do
      browser = nil
      begin
        # For some reason browsing or resolving will fail with the Unknown
        # error code if there's a service description ending with a period.
        # We'll try to avoid that issue by browsing for a service that is less
        # likely to exist outside of our control (_palacecontrol._tcp instead
        # of _http._tcp).  We also have to hard code port 80 below as a result.
        # See https://github.com/tenderlove/dnssd/issues/7
        service_type = '_palacecontrol._tcp'

        browser = DNSSD.browse! service_type do |service|
          unless service.flags.add?
            LogicStatusPage.remove_device service.name
            next
          end

          DNSSD.resolve service do |result|
            begin
              Timeout.timeout 1 do
                begin
                  addrs = Addrinfo.getaddrinfo(result.target, result.port,
                                               Socket::PF_INET, Socket::SOCK_STREAM)
                  dev = { :name => "#{result.target.sub(/\.$/,'')}",
                          :ip => addrs[0].ip_address,
                          :port => 80 } # TODO: Remove this workaround for Avahi-DNSSD bug
                  LogicStatusPage.add_device result.name, dev
                rescue SocketError => e
                end
              end
            rescue Timeout::Error
              n2log "Timeout when resolving address for #{result.target}"
            end
          end
        end
        at_exit do
          browser.stop if browser
        end
      rescue => boom
        n2log_e boom, "DNSSD Error"
        browser.stop if browser
        sleep 1
        start_network_browser
        Thread.exit
      end
    end

    at_exit do
      t.exit if t.alive?
    end
  end
end
