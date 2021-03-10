/*
 * JavaScript for attached hardware display.
 * (C)2012 Mike Bourgeous
 *
 * Depends on jQuery and the other Automation Controller scripts.
 */

// TODO: Split this into multiple files, then use something like Google Closure
// Compiler to compile, optimize, and minifiy it.

var LS = window.LS || {};
LS.USBTree = LS.USBTree || {};

LS.USBTree.svgns = "http://www.w3.org/2000/svg";

LS.USBTree.deviceTypes = {
	// width: initial width in pixels of iframe (will be replaced by width from .svg file)
	// height: initial height in pixels of iframe (will be replaced by height from .svg file)
	// margin: number of pixels between device outline and the edge of the iframe/svg canvas
	// corner: horizontal offset of port area (typically the radius of rounded corners)

	controller: {
		width: 114,
		height: 192,
		margin: 2,
		corner: 14,
		src: '/images/devices/vector_overhead_controller.svg',
		name: 'Automation Controller',
	},
	device: {
		width: 100,
		height: 76,
		margin: 2,
		corner: 14,
		src: '/images/devices/vector_overhead_device.svg',
		name: 'Unknown Device',
	},
};


LS.USBTree.portTypes = {
	// width: total width to add to device, including padding around port
	// offsetX: horizontal offset to add to port graphics
	// offsetY: vertical offset to add to port graphics
	// id: svg ID of port cutout and port graphics
	// leds: information about port LEDs:
	// 	offsetX: offset from left side of port graphics
	// 	offsetY: offset from top of port graphics
	// 	id: svg ID of LEDs to use
	// connector: information about connector to use for wires connected to ports
	// 	offsetX: offset from left side of port graphics
	// 	offsetY: offset from top of port graphics
	// 	id: svg ID of connector

	// TODO: Use and expand generic cutouts for flat ports?
	// TODO: Figure out why moveToOrigin() requires the half pixel offset for LEDs but not for port cutouts

	usb: { width: 36,
		offsetX: 4,
		offsetY: -3,
		id: 'usb_port',
		leds: {
			offsetX: 3.5,
			offsetY: -6.5,
			id: 'usb_port_leds',
		},
		connector: {
			offsetX: 1,
			offsetY: 0,
			id: 'front_usb',
		},
	},
	serial: { width: 54,
		offsetX: 4,
		offsetY: -3,
		id: 'serial_port',
		leds: {
			offsetX: 12.5,
			offsetY: -6.5,
			id: 'serial_port_leds',
		},
	},
};


// Represents a row in the hardware tree.
LS.USBTree.Row = function(index) {
	this.index = index;
	this.devices = [];
	this.section = document.createElement('section');
	this.section.id = 'usbtree_row' + index;
};
LS.USBTree.Row.prototype = {
	addDevice: function(device) {
		this.devices.push(device);
		this.section.appendChild(device.iframe);
		// TODO: Insert devices as sorted by devpath (this puts them in parent hub port order)
	},

	removeDevice: function(device) {
		this.section.removeChild(device.iframe);
		this.devices.splice(this.devices.indexOf(device), 1);
	},

	// Returns the total width in pixels of all devices on this row, including margins.
	getWidth: function() {
		var width = 0;

		for(var i = 0; i < this.devices.length; i++) {
			width += parseInt(this.devices.iframe.width);
		}

		return width;
	},
};

LS.USBTree.rows = [];
LS.USBTree.devices = [];
LS.USBTree.addDevice = function(device) {
	if(LS.USBTree.rows.length <= device.row) {
		var tree = document.getElementById('usbtree');
		for(var i = LS.USBTree.rows.length; i <= device.row; i++) {
			LS.USBTree.rows[i] = new LS.USBTree.Row(i);
			tree.appendChild(LS.USBTree.rows[i].section);
		}
	}

	LS.USBTree.rows[device.row].addDevice(device);

	LS.USBTree.devices.push(device);

	// TODO: Update wires
};
LS.USBTree.removeDevice = function(device) {
	LS.USBTree.rows[device.row].removeDevice(device);

	if(LS.USBTree.rows[device.row].length == 0) {
		var row = LS.USBTree.rows[device.row].splice(device.row, 1)[0];
		row.section.parentElement.removeChild(row.section);
	}

	// TODO: Update wires
};

// Creates a wire connecting the given points (y1 < y2), adds it to the #wires
// svg canvas, and returns the group that contains it.
LS.USBTree.drawWire = function(x1, y1, x2, y2) {
	var yc = (y2 + y1) / 2;
	var path = 'M ' + x1 + ',' + y1 +
		' L ' + x1 + ',' + (y1 + 2) +
		' C ' + x1 + ',' + yc +
		' ' + x2 + ',' + yc +
		' ' + x2 + ',' + (y2 - 1) +
		' L ' + x2 + ',' + y2;

	var g = document.createElementNS(LS.USBTree.svgns, 'g');
	
	var border = document.createElementNS(LS.USBTree.svgns, 'path');
	border.setAttribute('d', path);
	border.className.baseVal = 'wire_border';
	g.appendChild(border);

	var outer = document.createElementNS(LS.USBTree.svgns, 'path');
	outer.setAttribute('d', path);
	outer.className.baseVal = 'wire_outer';
	g.appendChild(outer);

	var inner = document.createElementNS(LS.USBTree.svgns, 'path');
	inner.setAttribute('d', path);
	inner.className.baseVal = 'wire_inner';
	g.appendChild(inner);

	LS.USBTree.wires[0].appendChild(g);

	return g;
};

// A wire connecting a device to a port on a parent device.
LS.USBTree.Wire = function(fromDev, fromPort, toDev) {
	if(toDev.row != fromDev.row - 1) {
		throw "toDev is not on row below fromDev.";
	}
	if(fromDev.ports[fromPort] == null) {
		throw "fromDev does not have a port " + fromPort;
	}
	if(fromDev.ports[fromPort].wire != null) {
		throw "fromDev already has a wire at port " + fromPort;
	}
	if(toDev.inWire != null) {
		throw "toDev already has a wire";
	}

	this.fromDev = fromDev;
	this.fromPort = fromPort;
	this.toDev = toDev;

	this.wire = drawWire(15, 15, 75, 75); // XXX/TODO: Actual coordinates

	fromDev.ports[fromPort].showConnector();
	fromDev.ports[fromPort].wire = this;
	toDev.inWire = this;
};
LS.USBTree.Wire.prototype = {
	// Updates the given wire in response to a layout or window size change
	update: function() {
		// TODO: Get location of parent port and destination outline
		// TODO: Update wire path element endpoints
	},

	// Removes this wire from the tree.
	remove: function() {
		this.wire.parentElement.removeChild(this.wire);

		this.fromDev.ports[this.fromPort].wire = null;
		this.fromDev.ports[this.fromPort].hideConnector();
		this.toDev.inWire = null;
	},
};
LS.USBTree.updateWires = function() {	
};


// Repositions the given svg element to the origin of its containing space,
// removing any transformations, and adding twice the element's height to
// ensure it is invisible.  Takes note of whether an element has already been
// transformed, so elements are only transformed once.
LS.USBTree.moveToOrigin = function(svgElem) {
	if(svgElem.getAttribute('data-usbxform')) {
		console.log('' + svgElem + ' ' + svgElem.id + ' already transformed');
		return;
	} else {
		console.log('' + svgElem + ' ' + svgElem.id + ' not yet transformed');
	}

	var baseBox = svgElem.getBBox();
	svgElem.transform.baseVal.clear();
	var baseX = -(baseBox.x - 0.5);
	var baseY = -(baseBox.y + Math.floor(baseBox.height) * 2 - 0.5);
	svgElem.setAttribute('transform', 'translate(' + baseX + ',' + baseY + ')');

	svgElem.setAttribute('data-usbxform', true);
};

// Creates a new <use> element referencing the given ID, with the given x and y
// coordinates.
LS.USBTree.createUse = function(id, x, y) {
	var use = document.createElementNS(LS.USBTree.svgns, 'use');
	use.href.baseVal = '#' + id;
	use.x.baseVal.value = x;
	use.y.baseVal.value = y;
	return use;
};

// Creates a port of the given type, adding it to the given device's svg
// element, and adding offset to its horizontal position.
LS.USBTree.Port = function(device, type, offset) {
	var doc = device.iframe.contentDocument;

	this.info = LS.USBTree.portTypes[type];
	if(this.info == null) {
		throw 'Unknown port type: ' + type;
	}

	this.device = device;

	var baseX = this.info.offsetX + device.info.margin + device.info.corner + offset;
	var baseY = this.info.offsetY + device.outlineBottom;

	this.base = doc.getElementById(this.info.id);
	LS.USBTree.moveToOrigin(this.base);

	this.port = LS.USBTree.createUse(
			this.info.id,
			baseX,
			baseY + Math.floor(this.base.getBBox().height) * 2
			);
	device.svg.appendChild(this.port);

	if(this.info.leds) {
		this.ledBase = doc.getElementById(this.info.leds.id);
		LS.USBTree.moveToOrigin(this.ledBase);

		this.leds = LS.USBTree.createUse(
				this.info.leds.id,
				baseX + this.info.leds.offsetX,
				baseY + Math.floor(this.ledBase.getBBox().height) * 2 + this.info.leds.offsetY
				);
		device.svg.appendChild(this.leds);
	}

	if(this.info.connector) {
		this.connectorBase = doc.getElementById(this.info.connector.id);
		LS.USBTree.moveToOrigin(this.connectorBase);

		this.connector = LS.USBTree.createUse(
				this.info.connector.id,
				baseX + this.info.connector.offsetX,
				baseY + Math.floor(this.connectorBase.getBBox().height) * 2 + this.info.connector.offsetY
				);
		device.svg.appendChild(this.connector);

		this.connector.style.visibility = 'hidden';
	}
};
LS.USBTree.Port.prototype = {
	// Shows this port's connector.
	showConnector: function() {
		if(this.connector) {
			this.connector.style.visibility = null;

			var height = parseInt(this.device.iframe.height);
			var minHeight = this.device.outlineBottom +
				this.device.info.margin +
				this.connectorBase.getBBox().height +
				this.info.offsetY +
				this.info.connector.offsetY +
				1; // 1 for stroke width around connector
			if(height < minHeight) {
				this.device.addFrameHeight(minHeight - height);
			}
		}
	},

	// Hides this port's connector.
	hideConnector: function() {
		if(this.connector) {
			this.connector.style.visibility = 'hidden';
		}

		// TODO: Shrink device if no connectors are visible
	},
};


// Moves all path nodes to the right of the middle of the given SVGPathElement
// by the specified amount, which may be negative.  If toLeft is truthy, then
// the nodes to the left of center will be moved instead.  The toLeft parameter
// is only useful if a scale or matrix transformation has flipped the path
// horizontally.
LS.USBTree.addWidth = function(pathElement, delta, toLeft) {
	var list = pathElement.pathSegList;
	var minX = list.getItem(0).x, maxX = list.getItem(0).x;

	if(toLeft) {
		delta = -delta;
	}

	// Find the middle
	for(var i = 1; i < list.numberOfItems; i++) {
		var item = list.getItem(i);
		if(item.x < minX) {
			minX = item.x;
		}
		if(item.x > maxX) {
			maxX = item.x;
		}
	}

	var middle = (minX + maxX) / 2;

	// Move the right half of the nodes
	for(var i = 0; i < list.numberOfItems; i++) {
		var item = list.getItem(i);

		if((!toLeft && item.x > middle) || (toLeft && item.x < middle)) {
			item.x += delta;
			if(item.x1) {
				item.x1 += delta;
			}
			if(item.x2) {
				item.x2 += delta;
			}
		}
	}
}


// Base class for devices in the hardware tree.
LS.USBTree.BaseDevice = function(type) {
	this.info = LS.USBTree.deviceTypes[type];
	this.type = type;
}
LS.USBTree.BaseDevice.prototype = {
	// Creates the iframe and sets up instance-specific data for this
	// device.  Call this in the subclass constructor.
	subclass_init: function() {
		var that = this;

		this.iframe = document.createElement('iframe');
		LS.frameload(this.iframe, function(){ that.image_loaded.call(that); });
		this.iframe.width = this.info.width;
		this.iframe.height = this.info.height;
		this.iframe.src = this.info.src;
		this.iframe.className = this.type;
		$(this.iframe).attr('data-name', this.devnode.name);
		$(this.iframe).attr('data-devpath', this.devnode.devpath);
		$(this.iframe).data('owner', this);

		this.ports = [];
		this.portWidth = 0;

		this.loaders = [];
		this.leftDelta = 0;
		this.rightDelta = 0;
	},

	// Sets up this device when its iframe has loaded.
	image_loaded: function() {
		if(this.loaded) {
			return;
		}

		var jq = $(this.iframe).contents();

		// The [0] is necessary for the ||
		this.title = jq.find('#title')[0] || jq.find('#title1')[0];
		this.title = this.title && $(this.title);

		this.svg = jq.find('svg')[0];

		this.outline = jq.find('#controller_outline')[0] || jq.find('#usb_hub_outline')[0] || jq.find('#device_enclosure_outline')[0];

		var outlineBox = this.outline.getBBox();
		this.outlineBottom = Math.floor(outlineBox.height + outlineBox.y + 0.5);

		this.grooves = jq.find('#usb_hub_grooves')[0] || jq.find('#device_enclosure_grooves')[0];

		var svgWidth = parseInt(jq.find('svg').attr('width'));
		var svgHeight = parseInt(jq.find('svg').attr('height'));

		this.iframe.width = svgWidth;
		this.iframe.height = svgHeight;
		this.iframe.style.width = svgWidth + 'px';
		this.iframe.style.height = svgHeight + 'px';

		this.baseWidth = svgWidth;
		this.baseHeight = svgHeight;

		this.loaded = true;

		if(this.title != null && this.titleText != null) {
			this.setTitle(this.titleText);
		}

		this.addWidth(this.leftDelta, true);
		this.addWidth(this.rightDelta, false);

		for(var i = 0; i < this.loaders.length; i++) {
			this.loaders[i](this);
		}

		var ports = this.ports;
		this.ports = [];
		for(var i = 0; i < ports.length; i++) {
			console.log("Adding stored port " + (i + 1));
			this.addPort(ports[i]);
		}
	},

	// Sets this device's title text.
	setTitle: function(text) {
		// TODO: HTML overlay into a specified container
		// See http://stackoverflow.com/questions/12462036/dynamically-insert-foreignobject-into-svg-with-jquery
		this.titleText = text;
		if(this.loaded && this.title) {
			this.title.text(text);

			var titlebox = this.title[0].getBBox();
			var outlinebox = this.outline.getBBox();
			if(titlebox.width != outlinebox.width - 16) {
				var currentWidth = parseInt(this.iframe.width);
				var delta = titlebox.width - outlinebox.width + 16;
				var min = this.baseWidth - currentWidth;
				this.addWidth(Math.max(min, delta));
			}
			// TODO:Re-center ports (and/or just wrap long titles?)
		}
	},

	// Adds delta (which may be negative) to the width of this device, by
	// moving all control points on the right half of the devices outline
	// and decorations (or left half, if toLeft is true).
	addWidth: function(delta, toLeft) {
		delta = parseInt(delta);
		if(!this.loaded) {
			if(toLeft) {
				this.leftDelta += delta;
			} else {
				this.rightDelta += delta;
			}

			return;
		}
		if(this.outline) {
			LS.USBTree.addWidth(this.outline, delta, toLeft);
		}
		if(this.grooves) {
			LS.USBTree.addWidth(this.grooves, delta, toLeft);
		}
		if(this.title) {
			this.title.attr('x', 0.5 * (parseInt(this.iframe.width) + delta));
			this.title.find('tspan').attr('x', parseFloat(this.title.find('tspan').attr('x')) + delta * 0.5);
		}
		this.iframe.width = parseInt(this.iframe.width) + delta;
		this.iframe.style.width = '' + this.iframe.width + 'px';
		this.svg.width.baseVal.value = parseInt(this.svg.width.baseVal.value) + delta;
	},

	// Adds delta to the height of the iframe and svg elements that contain
	// this device.
	addFrameHeight: function(delta) {
		var height = parseInt(this.iframe.height) + delta;
		this.iframe.height = height;
		this.iframe.style.height = '' + height + 'px';
		this.svg.height.baseVal.value = height;
	},

	// Adds one of the given port type (e.g. 'usb', 'serial') to this device.
	addPort: function(type) {
		if(!this.loaded) {
			console.log("Storing port " + (this.ports.length + 1));
			if(LS.USBTree.portTypes[type] == undefined) {
				throw "Unknown port type: " + type;
			}
			this.ports.push(type);
			return;
		}

		console.log("Creating port " + (this.ports.length + 1));

		var port = new LS.USBTree.Port(this, type, this.portWidth);
		this.portWidth += port.info.width;

		var minWidth = 2 * (this.info.corner + this.info.margin) + this.portWidth;
		if(this.baseWidth < minWidth) {
			this.baseWidth = minWidth;
		}
		if(this.baseWidth > this.iframe.width) {
			this.addWidth(this.baseWidth - this.iframe.width);
		}

		this.ports.push(port);
	},

	// Calls the given function after this device's SVG has loaded, or
	// immediately if the SVG is already loaded.
	onLoad: function(func) {
		if(this.loaded) {
			func(this);
		} else {
			this.loaders.push(func);
		}
	},
}

// A controller.
LS.USBTree.Controller = function(devnode) {
	this.devnode = devnode;
	this.row = devnode.row;
	this.titleText = devnode.devpath;
	this.subclass_init();
}
LS.USBTree.Controller.prototype = new LS.USBTree.BaseDevice('controller');

// A USB hub.
LS.USBTree.USBHub = function(devnode) {
	this.devnode = devnode;
	this.row = devnode.row;
	this.titleText = devnode.name || ('' + devnode.numports + '-port Hub');
	this.subclass_init();
	this.iframe.className = 'usb_hub';
	for(var i = 0; i < devnode.numports; i++) {
		console.log("Adding usb port " + (i + 1));
		this.addPort('usb');
	}
}
LS.USBTree.USBHub.prototype = new LS.USBTree.BaseDevice('device');

// A generic or unknown USB device.
LS.USBTree.Device = function(devnode) {
	this.devnode = devnode;
	this.row = devnode.row;
	this.titleText = devnode.name || devnode.devpath;
	this.subclass_init();
}
LS.USBTree.Device.prototype = new LS.USBTree.BaseDevice('device');


// Adds a device or port to the tree as appropriate for the given device and
// its parent usb_device
LS.USBTree.handleDevNode = function(dev, devparent) {
	if(dev.type == 'usb_bus') {
		console.log("new bus: " + dev.name + " ports: " + dev.numports);
		var controller = new LS.USBTree.Controller(dev);
		LS.USBTree.addDevice(controller);
	} else if(dev.type == 'usb_hub') {
		console.log("new hub: " + dev.name + " ports: " + dev.numports);
		var hub = new LS.USBTree.USBHub(dev);
		LS.USBTree.addDevice(hub);

		// TODO: Allow merging daisy-chained hubs?

	} else if(dev.type == 'usb_device') {
		console.log("new device: " + (dev.name || dev.devpath));

		// TODO: Detect device types, create a database mapping
		// device attributes to images, allow multiple devices
		// to be subsumed into a single image (e.g. the Kinect
		// with its 3-port hub, camera, audio, and motor
		// controller)

		var device = new LS.USBTree.Device(dev);
		LS.USBTree.addDevice(device);
	} else if(dev.type == 'other') {
		// TODO: Add support for more types of ports, use better criteria for detecting port type
		if(dev.devnodes && dev.devnodes.length > 0 && dev.devnodes[0].match(/ttyUSB/)) {
			console.log('Adding a serial port to ' + dev.parent_device);
			var device = $('[data-devpath="' + dev.parent_device + '"]').data('owner');
			device.addPort('serial');
		}
	}

	for(var i = 0; i < dev.children.length; i++) {
		var child = dev.children[i];
		var current = dev;
		LS.USBTree.handleDevNode(child, current);
	}
}

// Processes the devices in an array of trees returned as JSON from /hw/tree.
LS.USBTree.handleTree = function(jsonData) {
	for(i = 0; i < jsonData.length; i++) {
		LS.USBTree.handleDevNode(jsonData[i]);
	}
}

$(function() {
	LS.USBTree.usbtree = $('#usbtree');
	LS.USBTree.wires = $('#wires');

	$(window).resize(LS.USBTree.updateWires);

	$.get('/hw/tree').success(function(data) {
		LS.USBTree.handleTree(data);
	}).error(function(data) {
		alert('error, man'); // TODO: Better error handling (show error message like exports view)
	});
});
