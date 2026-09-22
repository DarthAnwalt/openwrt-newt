'use strict';
'require form';
'require poll';
'require rpc';
'require ui';
'require view';

const callStatus = rpc.declare({
	object: 'luci.pangolin-newt',
	method: 'get_status',
	expect: { '': {} }
});

const callLog = rpc.declare({
	object: 'luci.pangolin-newt',
	method: 'get_log',
	expect: { '': { log: '' } }
});

const callAction = rpc.declare({
	object: 'luci.pangolin-newt',
	method: 'service_action',
	params: [ 'action' ],
	expect: { '': { success: false } }
});

const callPackageStatus = rpc.declare({
	object: 'luci.pangolin-newt',
	method: 'get_package_status',
	expect: { '': {} }
});

const callPackageAction = rpc.declare({
	object: 'luci.pangolin-newt',
	method: 'package_action',
	params: [ 'action' ],
	expect: { '': { success: false } }
});

function text(value) {
	return document.createTextNode(value == null ? '-' : String(value));
}

function formatUptime(seconds) {
	if (seconds == null)
		return '-';

	let days = Math.floor(seconds / 86400);
	let hours = Math.floor((seconds % 86400) / 3600);
	let minutes = Math.floor((seconds % 3600) / 60);
	let parts = [];

	if (days)
		parts.push(days + 'd');
	if (hours || days)
		parts.push(hours + 'h');
	parts.push(minutes + 'm');

	return parts.join(' ');
}

function statusValue(id, label, good) {
	return E('span', {
		'id': id,
		'class': good ? 'label success' : 'label'
	}, [ text(label) ]);
}

function setStatusNode(id, label, good) {
	let node = document.getElementById(id);
	if (!node)
		return;

	node.className = good ? 'label success' : 'label';
	node.replaceChildren(text(label));
}

function updateStatus(status, logData) {
	status = status || {};
	setStatusNode('newt-running', status.running ? _('Running') : _('Stopped'), status.running);
	setStatusNode('newt-connected', status.connected ? _('Connected') : _('Disconnected'), status.connected);

	let pid = document.getElementById('newt-pid');
	let uptime = document.getElementById('newt-uptime');
	let version = document.getElementById('newt-version');
	let log = document.getElementById('newt-log');

	if (pid)
		pid.replaceChildren(text(status.pid));
	if (uptime)
		uptime.replaceChildren(text(formatUptime(status.uptime)));
	if (version)
		version.replaceChildren(text(status.version));
	if (log)
		log.replaceChildren(text(logData?.log || _('No log entries.')));
}

function updatePackageStatus(status) {
	status = status || {};
	let known = !!status.installed_newt && !!status.available_newt;
	let running = !!status.update_running;
	let failed = status.update_state == 'error';

	let installed = document.getElementById('newt-package-installed');
	let available = document.getElementById('newt-package-available');
	let state = document.getElementById('newt-package-update-state');
	let checkButton = document.getElementById('newt-package-check');
	let installButton = document.getElementById('newt-package-install');
	let output = document.getElementById('newt-package-output');

	if (installed)
		installed.replaceChildren(text(status.installed_newt));
	if (available)
		available.replaceChildren(text(status.available_newt));
	if (state) {
		state.className = running || status.update_available ? 'label notice' :
			(failed || !known ? 'label warning' : 'label success');
		state.replaceChildren(text(running ? _('Package operation in progress') :
			(failed ? _('Last package operation failed') :
				(status.update_available ? _('Update available') :
					(known ? _('Up to date') : _('Availability unknown'))))));
	}
	if (checkButton)
		checkButton.disabled = running;
	if (installButton)
		installButton.disabled = running || !status.update_available;
	if (output) {
		output.style.display = failed && status.update_output ? '' : 'none';
		output.replaceChildren(text(status.update_output));
	}
}

return view.extend({
	handleServiceAction: function(action, event) {
		event.currentTarget.blur();
		return callAction(action).then(function(result) {
			if (!result.success)
				throw new Error(result.error || _('Service action failed'));

			return new Promise(function(resolve) {
				window.setTimeout(resolve, 700);
			});
		}).then(function() {
			return Promise.all([ callStatus(), callLog() ]);
		}).then(function(data) {
			updateStatus(data[0], data[1]);
		}).catch(function(error) {
			ui.addNotification(null, E('p', [ text(error.message) ]), 'error');
		});
	},

	handlePackageAction: function(action, event) {
		if (action == 'upgrade' &&
		    !window.confirm(_('Install the available Newt package update? The tunnel may briefly reconnect.')))
			return Promise.resolve();

		let button = event.currentTarget;
		button.blur();
		button.disabled = true;

		return callPackageAction(action).then(function(result) {
			if (!result.success)
				throw new Error(result.error || result.output || _('Package action failed'));

			updatePackageStatus(result.status);
			ui.addNotification(null, E('p', [ text(_('Package operation started. Status will update automatically.')) ]), 'info');
		}).catch(function(error) {
			ui.addNotification(null, E('p', [ text(error.message) ]), 'error');
		}).then(function() {
			return callPackageStatus();
		}).then(updatePackageStatus);
	},

	load: function() {
		return Promise.all([ callStatus(), callLog(), callPackageStatus() ]);
	},

	render: function(data) {
		let m = new form.Map('newt', _('Newt'),
			_('Pangolin tunnel client managed by OpenWrt procd and apk.'));
		let s = m.section(form.NamedSection, 'main', 'newt', _('Configuration'));
		s.anonymous = true;
		s.addremove = false;

		let o = s.option(form.Flag, 'enabled', _('Enable'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Value, 'endpoint', _('Endpoint'));
		o.placeholder = 'https://pangolin.example.com';
		o.rmempty = false;
		o.validate = function(sectionId, value) {
			if (!/^https?:\/\/[^\s]+$/.test(value || ''))
				return _('Enter an HTTP or HTTPS URL.');
			return true;
		};

		o = s.option(form.Value, 'id', _('Newt ID'));
		o.rmempty = false;

		o = s.option(form.Value, 'secret', _('Secret'));
		o.password = true;
		o.rmempty = false;

		o = s.option(form.ListValue, 'log_level', _('Log level'));
		o.value('DEBUG', _('Debug'));
		o.value('INFO', _('Info'));
		o.value('WARN', _('Warning'));
		o.value('ERROR', _('Error'));
		o.value('FATAL', _('Fatal'));
		o.default = 'INFO';
		o.rmempty = false;

		o = s.option(form.Value, 'local_endpoint_interfaces', _('Local endpoint interfaces'),
			_('Optional comma-separated allowlist of interface names whose addresses Newt may advertise as local endpoints. Leave empty to use all suitable interfaces.'));
		o.placeholder = 'br-lan,wwan';
		o.rmempty = true;
		o.validate = function(sectionId, value) {
			if (value && !/^[A-Za-z0-9_.:-]+(?:\s*,\s*[A-Za-z0-9_.:-]+)*$/.test(value))
				return _('Enter interface names separated by commas, for example br-lan,wwan.');
			return true;
		};

		let status = data[0] || {};
		let logData = data[1] || {};
		let packageStatus = data[2] || {};
		let packageStatusKnown = !!packageStatus.installed_newt && !!packageStatus.available_newt;
		let packageUpdateRunning = !!packageStatus.update_running;
		let packageUpdateFailed = packageStatus.update_state == 'error';
		let statusSection = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ text(_('Status')) ]),
			E('table', { 'class': 'table' }, [
				E('tr', {}, [ E('td', {}, [ text(_('Service')) ]), E('td', {}, [
					statusValue('newt-running', status.running ? _('Running') : _('Stopped'), status.running)
				]) ]),
				E('tr', {}, [ E('td', {}, [ text(_('Tunnel')) ]), E('td', {}, [
					statusValue('newt-connected', status.connected ? _('Connected') : _('Disconnected'), status.connected)
				]) ]),
				E('tr', {}, [ E('td', {}, [ text(_('Version')) ]), E('td', { 'id': 'newt-version' }, [ text(status.version) ]) ]),
				E('tr', {}, [ E('td', {}, [ text(_('PID')) ]), E('td', { 'id': 'newt-pid' }, [ text(status.pid) ]) ]),
				E('tr', {}, [ E('td', {}, [ text(_('Uptime')) ]), E('td', { 'id': 'newt-uptime' }, [ text(formatUptime(status.uptime)) ]) ])
			]),
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-apply',
					'click': ui.createHandlerFn(this, this.handleServiceAction, 'start')
				}, [ text(_('Start')) ]),
				' ',
				E('button', {
					'class': 'btn cbi-button cbi-button-negative',
					'click': ui.createHandlerFn(this, this.handleServiceAction, 'stop')
				}, [ text(_('Stop')) ]),
				' ',
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, this.handleServiceAction, 'restart')
				}, [ text(_('Restart')) ])
			])
		]);

		let packageSection = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ text(_('Package update')) ]),
			E('p', {}, [ text(_('Only the Newt and LuCI packages from the configured signed repository are checked and upgraded.')) ]),
			E('table', { 'class': 'table' }, [
				E('tr', {}, [ E('td', {}, [ text(_('Installed version')) ]), E('td', { 'id': 'newt-package-installed' }, [ text(packageStatus.installed_newt) ]) ]),
				E('tr', {}, [ E('td', {}, [ text(_('Available version')) ]), E('td', { 'id': 'newt-package-available' }, [ text(packageStatus.available_newt) ]) ]),
				E('tr', {}, [ E('td', {}, [ text(_('State')) ]), E('td', {}, [
					E('span', {
						'id': 'newt-package-update-state',
						'class': packageUpdateRunning || packageStatus.update_available ? 'label notice' :
							(packageUpdateFailed || !packageStatusKnown ? 'label warning' : 'label success')
					}, [ text(packageUpdateRunning ? _('Package operation in progress') :
						(packageUpdateFailed ? _('Last package operation failed') :
							(packageStatus.update_available ? _('Update available') :
								(packageStatusKnown ? _('Up to date') : _('Availability unknown'))))) ])
				]) ])
			]),
			E('pre', {
				'id': 'newt-package-output',
				'style': (packageUpdateFailed && packageStatus.update_output ? '' : 'display:none;') +
					'max-height:12em;overflow:auto;white-space:pre-wrap'
			}, [ text(packageStatus.update_output) ]),
			E('div', { 'class': 'right' }, [
				E('button', {
					'id': 'newt-package-check',
					'class': 'btn cbi-button cbi-button-action',
					'disabled': packageUpdateRunning,
					'click': ui.createHandlerFn(this, this.handlePackageAction, 'check')
				}, [ text(_('Check for updates')) ]),
				' ',
				E('button', {
					'id': 'newt-package-install',
					'class': 'btn cbi-button cbi-button-apply',
					'disabled': packageUpdateRunning || !packageStatus.update_available,
					'click': ui.createHandlerFn(this, this.handlePackageAction, 'upgrade')
				}, [ text(_('Install update')) ])
			])
		]);

		let logSection = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ text(_('Recent log')) ]),
			E('pre', {
				'id': 'newt-log',
				'style': 'max-height:24em;overflow:auto;white-space:pre-wrap'
			}, [ text(logData.log || _('No log entries.')) ])
		]);

		poll.add(function() {
			return Promise.all([ callStatus(), callLog(), callPackageStatus() ]).then(function(values) {
				updateStatus(values[0], values[1]);
				updatePackageStatus(values[2]);
			});
		}, 5);

		return m.render().then(function(formNode) {
			return E('div', {}, [ statusSection, formNode, packageSection, logSection ]);
		});
	}
});
