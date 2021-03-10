/*
 * Utility functions for logic system web interface.
 * (C)2012 Mike Bourgeous
 */

var console = console || { log: function(){}, error: function(){}, dir: function(){} };

var LS = window.LS || {};

// Escapes essential HTML characters in the given text with their &.*;
// equivalents.
LS.escape = function(text) {
	return text.toString().replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// Calls the given function after a delay if the given iframe has loaded,
// otherwise sets an onload handler.
LS.frameload = function(frame, func) {
	if(frame.contentWindow != null && frame.contentWindow.document.readyState == "complete") {
		setTimeout(func, 1);
	} else {
		$(frame).load(func);
	}
}
