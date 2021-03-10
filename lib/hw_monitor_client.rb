#!/usr/bin/env ruby
# Ruby client interface for the libudev-based hardware monitoring program in
# programs/hw_monitor.c.  It is executable for stand-alone testing.
# (C)2012 Mike Bourgeous

require 'eventmachine'
require 'nl/logic_client' # for KeyValueParser - TODO: use C-based kvp

class Array
  # Inserts the given item into this array, which must already be sorted.  The
  # item will be inserted according to its natural order if no block is given.
  # If a block is given, the item will be inserted before the first item in the
  # array for which the block returns true.
  def insert_sorted item, &by
    idx = block_given? ? find_index(&by) : find_index { |d| d > item }
    idx ||= length
    insert idx, item
  end
end

module HwMonitorClient
  # Starts hw_monitor (provided by logic_system) and returns the initial
  # HwClient that will receive its input.  If for some reason hw_monitor dies,
  # it will be restarted, and all old event listeners will be attached to the
  # new HwClient (the originally returned HwClient reference will be invalid at
  # this point).
  def self.start
    client = EM.popen("hw_monitor", HwClient)

    client.add_listener { |event, device|
      if event == :unbind
        HwMonitorClient.print_error "Disconnected from hw_monitor"

        listeners = client.each_listener.to_a
        EM.add_timer(1) do
          puts "\e[1;32mReconnecting to hw_monitor\e[0m"

          new_client = EM.popen("hw_monitor", HwClient)
          listeners.each do |l|
            new_client.add_listener true, l
          end

          client = new_client
        end
      end
    }

    client
  end

  # Prints an error message in red using ANSI escape sequences.
  def self.print_error msg
    puts "\e[0;31mError: \e[1m#{msg}\e[0m"
  end

  # Represents a device in the device tree.
  class Device < Hash
    # Initializes a Device object with the given hash, which could be another
    # Device, or a Hash parsed from a key-value line from hw_monitor.  Does not
    # handle linking to other parent/child/etc. devices.
    def initialize hash
      merge! hash
      self[:children] = []
      self[:features] = []
    end

    # Merges the other Device or Hash with this one, collecting 'devN' entries
    # (if any) into a single 'devnodes' array.
    def merge! other
      super

      devnodes = []
      idx = 1
      while include? "dev#{idx}"
        devnodes << self["dev#{idx}"]
        delete "dev#{idx}"
        idx += 1
      end

      if devnodes.empty?
        delete 'devnodes'
      else
        self['devnodes'] = devnodes
      end
    end

    # Returns a string representation of this device.  The output is similar to
    # Hash#inspect, but does not recurse into nested hashes and arrays.
    def to_s
      str = '{'
      first = true
      self.each do |k, v|
        str << ', ' unless first
        str << k.inspect
        str << '=>'
        if v.is_a? Hash
          str << '{...}'
        elsif v.is_a?(Array) && k != 'devnodes'
          str << "[#{v.size}]"
        else
          str << v.inspect
        end
        first = false
      end
      str << '}'

      return str
    end

    # Adds the given device to this device's list of children, if it is not
    # already present.
    def add_child device
      self[:children].insert_sorted device unless self[:children].include? device
    end

    # Removes the given device from this device's list of children, if it is
    # present.
    def remove_child device
      self[:children].delete device
    end

    # Adds the given device to this device's list of features (devices which
    # represent drivers bound to the physical device), if it is not already
    # present.
    def add_feature device
      self[:features].insert_sorted device unless self[:features].include? device
    end

    # Removes the given device from this device's list of features, if it is
    # present.
    def remove_feature device
      self[:features].delete device
    end

    # Returns a copy of this device with all links to other devices removed
    # (e.g. to allow conversion to JSON).
    def clean
      device = self.clone
      device.clean!
      device
    end

    # Deletes all links to other devices from this device.
    def clean!
      delete :parent_hash
      delete :parent_device_hash
      delete :children
      delete :features
    end

    # Returns a JSON representation of this device, without any of its
    # children, features, or parents included.  Will only work if a JSON
    # library has been loaded.
    def to_json *args
      {}.replace(clean()).to_json *args
    end

    # Returns nil if other is not a Device, -1 if this device should come
    # before the other device lexicographically, 0 if the devices have the same
    # devpath, 1 if this device should come after the other device.
    def <=> other
      return nil unless other.is_a? Device
      self['devpath'] <=> other['devpath']
    end

    # Returns true if this device's devpath should come before the other device
    # in a lexicographical ordering.
    def < other
      self['devpath'] < other['devpath']
    end

    # Returns true if this device's devpath should come after the other device
    # in a lexicographical ordering.
    def > other
      self['devpath'] > other['devpath']
    end

    # Returns true if this device's devpath is equal to the other device's
    # devpath.
    def == other
      self['devpath'] == other['devpath']
    end
  end

  # Handler for input from hw_monitor.  Input from hw_monitor is similar to
  # incoming lines from the logic system and knd.  It has the following form:
  #
  # (ADD|CHANGE|ONLINE|OFFLINE|REMOVE) devpath="/devices/..." ...
  #
  # The first word is the type of event, indicating whether a device is being
  # added, changed, removed, etc.  The rest of the line is a list of possibly
  # quoted key-value pairs.  All events include the devpath key, which is the
  # system's unique identifier for a device.  ADD and CHANGE events also
  # include detailed information about the device, such as its type, USB speed,
  # device nodes in /dev (if any), etc.
  class HwClient < EM::P::LineAndTextProtocol
    def post_init
      @roots = []
      @devices = {}
      @listeners = []
    end

    def unbind
      each_device nil, 0, true do |dev|
        send_event :remove, dev
      end

      send_event :unbind, self

      @roots.clear
      @devices.clear
      @listeners.clear
    end

    def receive_line line
      line = line.force_encoding('UTF-8')
      begin
        event, device = line.split(' ', 2)

        device = Device.new NL::LC::KVP.kvp(device)

        devpath = device['devpath']

        case event
        when 'ADD'
          @devices[devpath] = device

          if device.include? 'parent'
            parent = @devices[device['parent']]
            device[:parent_hash] = parent

            if device['type'] == 'usb_device' || device['type'] == 'usb_hub'
              device[:row] = parent[:row] + 1
            end

            parent.add_child device

            if device['parent_device']
              # This is a feature on a physical device
              parent_device = @devices[device['parent_device']]
              device[:parent_device_hash] = parent_device
              parent_device.add_feature device
            end
          else
            device[:row] = 0
            @roots.insert_sorted device
          end

          send_event :add, device

        when 'CHANGE'
          @devices[devpath].merge! device
          send_event :change, @devices[devpath]

        when 'ONLINE'
          send_event :online, @devices[devpath]

        when 'OFFLINE'
          send_event :offline, @devices[devpath]

        when 'REMOVE'
          device = @devices[devpath]
          @devices.delete devpath
          if device.include? :parent_hash
            device[:parent_hash].remove_child device
          else
            @roots.delete device
          end
          device[:parent_device_hash].remove_feature device if device[:parent_device_hash]
          send_event :remove, device
        end
      rescue => e
        HwMonitorClient.print_error "#{e} - #{e.backtrace}"
      end
    end

    def receive_error error
      HwMonitorClient.print_error "#{error} (or exception raised)"
    end

    # Adds the given block to be called when an event is received.  If catch_up
    # is true (the default), then the block will be called with :add events for
    # all existing devices.  The block will be called with the event type as
    # the first parameter and a device hash as the second, if applicable.  The
    # device hashes passed to the block should not be modified.  The callable
    # object passed in the listener parameter or a Proc generated from the
    # given block will be returned for use with remove_listener().
    #
    # The :bind event will be passed to the listener as soon as it is added for
    # the first time, with the HwClient as parameter.  This allows users to get
    # the current HwClient in the event of a reconnection to hw_monitor.
    #
    # Device events: :add, :change, :online, :offline, :remove
    #
    # Connection events: :bind, :unbind
    def add_listener catch_up=true, listener=nil, &block
      if listener != nil && block_given?
        raise "Both a listener and a block were given."
      end
      if listener == nil && !block_given?
        raise "Neither a listener nor a block were given."
      end

      listener = block if block_given?

      raise "Listener must respond to :call (e.g. a Proc object)" unless listener.respond_to? :call

      if !(@listeners.include? block)
        @listeners << listener
      end

      listener.call :bind, self

      if catch_up
        each_device do |v|
          listener.call :add, v
        end
      end

      listener
    end

    # Removes the given event listener, if present.  Either pass the exact
    # value given in add_listener()'s listener parameter or add_listener()'s
    # return value.
    def remove_listener listener
      @listeners.delete listener
    end

    # Iterates over listeners if a block is given, returns an enumerator on the
    # list of listeners otherwise.
    def each_listener &block
      @listeners.each &block
    end

    # Recursively yields the given device and current depth, followed by all
    # its children, in depth-first order, to the given block.  Depth will be
    # incremented by one for each level in the tree.  If dev is nil, then every
    # device in the tree (which may have multiple roots) will be traversed in
    # depth-first order.  Devices on the same level of the tree will be
    # traversed in lexicographical order.  If reverse is true, then all leaf
    # nodes will be passed before branches.  The device hashes passed to the
    # should not be modified.
    def each_device dev=nil, depth=0, reverse=false, &block
      raise "A block must be given to each_device()." unless block_given?

      if dev.nil?
        @roots.each do |root|
          each_device root, depth, reverse, &block
        end
      else
        yield dev, depth unless reverse
        dev[:children].each do |child|
          each_device child, depth + 1, reverse, &block
        end
        yield dev, depth if reverse
      end
    end

    # Prints the device tree starting with the given device, or prints the
    # entire tree (including all roots if there is more than one parentless
    # device).
    def print_tree base=nil, depth=0
      each_device base, depth do |dev, level|
        puts "#{' ' * (level * 2)}\e[1;32m#{dev['devpath']} \e[1;33m#{dev['name']}\e[0m"
      end
    end

    # Returns an array containing all root devices in the device tree, sorted
    # lexicographically by their system device paths.  The returned array must
    # not be modified.
    def get_tree
      @roots
    end

    # Returns a JSON representation of the complete device tree.
    def to_json *args
      tree = []
      @roots.each do |dev|
        tree << tree_to_hash(dev)
      end
      tree.to_json *args
    end

    private
    # Sends the given event with the given device to all blocks added with
    # add_listener.
    def send_event event, device
      @listeners.each do |l|
        l.call event, device
      end
    end

    # Returns a Hash containing the given device and all its children, with
    # parent and feature links removed.
    def tree_to_hash device
      hash = {}.replace(device.clean)

      hash[:children] = []
      device[:children].each do |child|
        hash[:children] << tree_to_hash(child)
      end

      hash
    end
  end
end

if __FILE__ == $0
  # Run a simple test if invoked directly
  EM.run {
    puts "\e[0;32mStarting \e[1mHwMonitorClient\e[0m"
    HwMonitorClient.start().add_listener() do |event, source|
      puts "\e[1;34mReceived \e[35m#{event.inspect}\e[34m event: \e[1;36m#{source}\e[0m"
      if event == :unbind
        source.print_tree
      end
    end
  }
end
