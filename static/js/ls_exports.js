/*
 * Code for managing live updates of exported parameters.
 * (C)2012 Mike Bourgeous
 */

var LS = window.LS || {};

LS.EXP = LS.EXP || {};

LS.EXP.initExports = function(baseId) {
	console.log("Initializing live updates for exports on id " + baseId);
	var table = $('#table_' + baseId);
	var form = $('#form_' + baseId);
	var err = $('#err_' + baseId);

	function errorText(text) {
		if(text == null) {
			return err.text();
		}

		text = text.toString();
		if(text.length > 0) {
			console.log('Error text: ' + text);
			err.html(text);
			err.stop(true, true);
			if(err.is(':hidden')) {
				err.slideToggle(200);
			}
		} else {
			err.stop(true, true);
			if(err.is(':visible')) {
				err.slideToggle(200, function(){err.text('');});
			}
		}
	}

	// Sets up an export table row for live updates.  Pass in a
	// raw <tr> element.
	function setupRow(tr) {
		var row = $(tr);
		var input = row.find('input[data-value]');

		row.data('input', input);

		if(row.attr('data-hide') == 'true') {
			// TODO: Make hidden rows optionally visible
			row.remove();
			return;
		}

		// TODO: Reset value to row.attr('data-value') if escape is pressed

		input.change(function() {
			setExport(parseInt(row.attr('data-objid')), parseInt(row.attr('data-index')), input.attr('value'));
			if(input.is(':focus')) {
				input[0].select();
			}
		});
	}

	// row - the row to update
	// expInfo - the JSON object containing the export's info
	// force - whether to update even if focused (true if called from setExport())
	function updateRow(tr, expInfo, force) {
		var row = $(tr);

		if(row.attr('data-hide') && expInfo.hide_in_ui) {
			return;
		}

		var input = row.data('input');
		var focus = input.is(':focus');

		// Update the input value only if not focused or when just
		// changed by the user
		if(!focus || force) {
			input[0].value = expInfo.value;
			if(focus) {
				input[0].select();
			}
		}
		input.attr('data-value', expInfo.value);

		// TODO: Handle all other attributes and columns
	}

	// Creates a <tr> for the given index and export info object
	function createRow(idx, expInfo) {
		var tr = document.createElement('tr');
		var htmlStr = '';

		$(tr).attr('data-export', idx)
			.attr('data-objid', expInfo.objid)
			.attr('data-index', expInfo.index)
			.attr('data-type', expInfo.type)
			.attr('data-hide', expInfo.hide_in_ui);

		// TODO: Build using DOM methods
		htmlStr += '<td>' + idx + '</td>';
		htmlStr += '<td>' + expInfo.objId + ',' + expInfo.index + '</td>';
		htmlStr += '<td>' + LS.escape(expInfo.obj_name) + '</td>';
		htmlStr += '<td>' + LS.escape(expInfo.param_name) + '</td>';
		htmlStr += '<td>' + LS.escape(expInfo.type) + '</td>';

		htmlStr += '<td><input type="text" name="param_' + expInfo.objid + '_' + expInfo.index + '" ';
		htmlStr += 'data-value="' + LS.escape(expInfo.value).replace(/"/g, '&quot;') + '" ';
		htmlStr += 'value="' + LS.escape(expInfo.value).replace(/"/g, '&quot;') + '" ';
		if(expInfo.read_only) {
			htmlStr += 'disabled ';
		}
		if(expInfo.type == 'int') {
			htmlStr += 'min="' + expInfo.min + '" max="' + expInfo.max + '"';
		}

		$(tr).html(htmlStr);

		updateRow(tr, expInfo, true);

		return tr;
	}

	// exports - the JSON array containing the list of exports
	// force - whether to update an input even if it is focused (true if called from setExport())
	function handleExportsJSON(exports, force) {
		// FIXME: If the export list changes, that means the design was
		// changed.  Just blow away the table in that case.

		// FIXME: Updates don't work on phone.  Find out why.
		var rows = table.find('tr[data-export]');
		for(var i = 0; i < rows.length; i++) {
			// If the newly received exports do not include this row, delete the table row.
			var row = $(rows[i]);
			var remove = true;
			for(var j = i; j < exports.length; j++) {
				// FIXME: O(n^2), rows don't get removed
				if(exports[j].objid == parseInt(row.attr('data-objid')) &&
						exports[j].index == parseInt(row.attr('data-index'))) {
					remove = false;
					break;
				}
			}
			if(remove) {
				row.remove();
				rows.splice(i, 1);
				i--; // Counteract post-loop increment
			}
		}

		rows = table.find('tr[data-export]');
		for(var i = 0, j = 0; i < exports.length; i++, j++) {
			var row = $(rows[j]);
			// If the exports table doesn't have this export at this position, insert it.
			// Otherwise, update the existing row.

			if(exports[i].hide_in_ui) {
				j--;
				continue;
			}

			if(parseInt(row.attr('data-objid')) != exports[i].objid ||
					parseInt(row.attr('data-index')) != exports[i].index) {
				rows.splice(i, 0, createRow(i, exports[i]));
				row = $(rows[i]);
				if(i < rows.length - 1) {
					rows[i + 1].insertBefore(rows[i]);
				} else {
					var before = document.getElementById('submitrow_' + baseId);
					console.log("Inserting a new row before the submit row");
					console.dir(before);
					console.dir(rows[i]);
					before.insertBefore(rows[i]);
				}
			} else {
				updateRow(row, exports[i], force);
			}

			row.attr('data-export', i);
		}
	}

	function setExport(objid, index, value) {
		console.log("Setting " + objid + "," + index + " to " + value);

		var params = {redir: 0};
		params['param_' + objid + "_" + index] = value;
		$.post('/api/set', params).success(
			function(data) {
				if(errorText().match(/^Error setting object/)) {
					errorText('');
				}
				handleExportsJSON(data, true);
			})
		.error(
			function(data) {
				errorText("Error setting object " + objid + " parameter " + index + ": " +
					LS.escape(data.responseText).replace('\n', '<br>'));
			});
	}
	LS.EXP.setExport = setExport; // XXX: This is just for convenient testing from the console

	// Disable form submission and hide submit button
	form.submit(function(ev) { ev.preventDefault(); return false; });
	$('#submit_' + baseId).hide().attr('disabled', 'disabled');
	$('#submitrow_' + baseId).hide();

	table.find('tr[data-export]').each(function(idx, row) {
		setupRow(row);
	});

	// Export table update timer (TODO: Set up long polling on the server
	// side and reduce 500ms time below)
	var updateTimer;
	function updateExports() {
		$.get('/api/exports').success(function(data) {
			if(errorText().match(/^Error getting exported parameters/)) {
				errorText('');
			}
			handleExportsJSON(data, false);
			clearTimeout(updateTimer);
			updateTimer = setTimeout(updateExports, 500);
		}).error(function(data) {
			errorText("Error getting exported parameters from the controller.  " +
				"Make sure the controller is on.<br/>" + LS.escape(data.responseText));
			clearTimeout(updateTimer);
			updateTimer = setTimeout(updateExports, 2000);
		});
	}
	updateExports();
}
