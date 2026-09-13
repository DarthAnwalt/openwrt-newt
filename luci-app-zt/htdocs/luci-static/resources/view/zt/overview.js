'use strict';
'require form';
'require poll';
'require rpc';
'require ui';
'require view';

const callConfig = rpc.declare({
	object: 'luci.zt',
	method: 'get_config',
	expect: { '': { config: { global: {}, network: [] }, identity_secret_present: false } }
});

const callSetConfig = rpc.declare({
	object: 'luci.zt',
	method: 'set_config',
	params: [ 'config' ],
	expect: { '': { success: false } }
});

const callStatus = rpc.declare({
	object: 'luci.zt',
	method: 'get_status',
	expect: { '': {} }
});

const callNetworks = rpc.declare({
	object: 'luci.zt',
	method: 'get_networks',
	expect: { '': { success: false, networks: [] } }
});

const callLog = rpc.declare({
	object: 'luci.zt',
	method: 'get_log',
	expect: { '': { log: '' } }
});

const callServiceAction = rpc.declare({
	object: 'luci.zt',
	method: 'service_action',
	params: [ 'action' ],
	expect: { '': { success: false } }
});

const callPackageStatus = rpc.declare({
	object: 'luci.zt',
	method: 'get_package_status',
	expect: { '': {} }
});

const callPackageAction = rpc.declare({
	object: 'luci.zt',
	method: 'package_action',
	params: [ 'action' ],
	expect: { '': { success: false } }
});

function text(value) {
	return document.createTextNode(value == null || value === '' ? '-' : String(value));
}

function yesNo(value) {
	return value ? _('Yes') : _('No');
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

function networkRows(data) {
	let networks = data?.networks || [];

	if (!data?.success)
		return [ E('tr', {}, [ E('td', { 'colspan': '9' }, [ text(data?.error || _('Runtime information is unavailable.')) ]) ]) ];
	if (!networks.length)
		return [ E('tr', {}, [ E('td', { 'colspan': '9' }, [ text(_('No joined networks reported by the daemon.')) ]) ]) ];

	return networks.map(function(network) {
		let flags = [
			'M:' + yesNo(network.allow_managed),
			'G:' + yesNo(network.allow_global),
			'D:' + yesNo(network.allow_default),
			'DNS:' + yesNo(network.allow_dns)
		].join(' · ');

		return E('tr', {}, [
			E('td', {}, [ text(network.id) ]),
			E('td', {}, [ text(network.name) ]),
			E('td', {}, [ text(network.status) ]),
			E('td', {}, [ text(network.type) ]),
			E('td', {}, [ text(network.device) ]),
			E('td', {}, [ text((network.assigned_addresses || []).join(', ')) ]),
			E('td', {}, [ text(network.mac) ]),
			E('td', {}, [ text(network.mtu) ]),
			E('td', {}, [ text(flags) ])
		]);
	});
}

function updateRuntime(status, networks, logData) {
	status = status || {};
	setStatusNode('zt-running', status.running ? _('Running') : _('Stopped'), status.running);
	setStatusNode('zt-online', status.online ? _('Online') : _('Offline'), status.online);

	for (let field of [ 'node-id', 'version', 'pid' ]) {
		let node = document.getElementById('zt-' + field);
		if (node)
			node.replaceChildren(text(status[field.replace('-', '_')]));
	}

	let uptime = document.getElementById('zt-uptime');
	if (uptime)
		uptime.replaceChildren(text(formatUptime(status.uptime)));

	let body = document.getElementById('zt-runtime-networks');
	if (body)
		body.replaceChildren(...networkRows(networks));

	let log = document.getElementById('zt-log');
	if (log)
		log.replaceChildren(text(logData?.log || _('No log entries.')));
}

function packageStateLabel(status, kind) {
	let installed = status['installed_' + kind];
	let available = status['available_' + kind];
	let upgradable = status[kind + '_update_available'];

	if (!installed || !available)
		return _('Availability unknown');
	return upgradable ? _('Update available') : _('Up to date');
}

function updatePackageStatus(status) {
	status = status || {};
	let running = !!status.update_running;
	let failed = status.update_state == 'error';

	for (let kind of [ 'zerotier', 'luci' ]) {
		let installed = document.getElementById('zt-' + kind + '-installed');
		let available = document.getElementById('zt-' + kind + '-available');
		let state = document.getElementById('zt-' + kind + '-state');
		let button = document.getElementById('zt-' + kind + '-upgrade');
		let upgradable = !!status[kind + '_update_available'];
		let known = !!status['installed_' + kind] && !!status['available_' + kind];

		if (installed)
			installed.replaceChildren(text(status['installed_' + kind]));
		if (available)
			available.replaceChildren(text(status['available_' + kind]));
		if (state) {
			state.className = upgradable ? 'label notice' : (known ? 'label success' : 'label warning');
			state.replaceChildren(text(packageStateLabel(status, kind)));
		}
		if (button)
			button.disabled = running || !upgradable;
	}

	let operation = document.getElementById('zt-package-operation');
	if (operation) {
		operation.className = running ? 'label notice' : (failed ? 'label warning' : 'label success');
		operation.replaceChildren(text(running ? _('Package operation in progress') :
			(failed ? _('Last package operation failed') : _('Idle'))));
	}

	let checkButton = document.getElementById('zt-package-check');
	if (checkButton)
		checkButton.disabled = running;

	let output = document.getElementById('zt-package-output');
	if (output) {
		output.style.display = failed && status.update_output ? '' : 'none';
		output.replaceChildren(text(status.update_output));
	}
}

function exportConfiguration(map) {
	let source = map.data.data;
	let global = source.global || {};
	let networks = [];

	for (let name in source) {
		let section = source[name];
		if (section['.type'] != 'network')
			continue;

		networks.push({
			id: section.id || '',
			allow_managed: section.allow_managed || '1',
			allow_global: section.allow_global || '0',
			allow_default: section.allow_default || '0',
			allow_dns: section.allow_dns || '0'
		});
	}

	return {
		global: {
			enabled: global.enabled || '0',
			port: global.port || '',
			local_conf_path: global.local_conf_path || '',
			config_path: global.config_path || '',
			copy_config_path: global.copy_config_path || '0'
		},
		networks: networks
	};
}

return view.extend({
	saveConfiguration: function(restart) {
		return this.configMap.parse().then(L.bind(function() {
			return callSetConfig(exportConfiguration(this.configMap));
		}, this)).then(function(result) {
			if (!result.success)
				throw new Error(result.error || _('Unable to save ZeroTier configuration'));

			return restart ? callServiceAction('restart') : { success: true };
		}).then(function(result) {
			if (!result.success)
				throw new Error(result.error || _('Configuration was saved but ZeroTier could not be restarted'));

			ui.addNotification(null, E('p', [ text(restart ?
				_('Configuration saved and ZeroTier restarted.') :
				_('Configuration saved.')) ]), 'info');
		}).catch(function(error) {
			ui.addNotification(null, E('p', [ text(error.message) ]), 'error');
			return Promise.reject(error);
		});
	},

	handleSave: function() {
		return this.saveConfiguration(false);
	},

	handleSaveApply: function() {
		return this.saveConfiguration(true);
	},

	handleReset: function() {
		return this.configMap.reset();
	},

	handleServiceAction: function(action, event) {
		event.currentTarget.blur();
		return callServiceAction(action).then(function(result) {
			if (!result.success)
				throw new Error(result.error || _('Service action failed'));

			return new Promise(function(resolve) {
				window.setTimeout(resolve, 1000);
			});
		}).then(function() {
			return Promise.all([ callStatus(), callNetworks(), callLog() ]);
		}).then(function(data) {
			updateRuntime(data[0], data[1], data[2]);
		}).catch(function(error) {
			ui.addNotification(null, E('p', [ text(error.message) ]), 'error');
		});
	},

	handlePackageAction: function(action, event) {
		let message = action == 'upgrade_zerotier' ?
			_('Install the available ZeroTier update? Active ZeroTier connections will briefly disconnect while the daemon restarts.') :
			_('Install the available luci-app-zt update?');

		if (action != 'check' && !window.confirm(message))
			return Promise.resolve();

		let button = event.currentTarget;
		button.blur();
		button.disabled = true;

		return callPackageAction(action).then(function(result) {
			if (!result.success)
				throw new Error(result.error || _('Package action failed'));

			updatePackageStatus(result.status);
			ui.addNotification(null, E('p', [ text(_('Package operation started. Status will update automatically.')) ]), 'info');
		}).catch(function(error) {
			ui.addNotification(null, E('p', [ text(error.message) ]), 'error');
		}).then(function() {
			return callPackageStatus();
		}).then(updatePackageStatus);
	},

	load: function() {
		return Promise.all([ callConfig(), callStatus(), callNetworks(), callLog(), callPackageStatus() ]);
	},

	render: function(data) {
		let configData = data[0] || { config: { global: {}, network: [] } };
		let status = data[1] || {};
		let runtimeNetworks = data[2] || { success: false, networks: [] };
		let logData = data[3] || {};
		let packageStatus = data[4] || {};
		let m = new form.JSONMap(configData.config, _('ZeroTier'),
			_('Manage the official OpenWrt ZeroTier service without exposing its identity secret to the browser.'));
		this.configMap = m;

		let s = m.section(form.NamedSection, 'global', 'global', _('Configuration'));
		s.anonymous = true;
		s.addremove = false;

		let o = s.option(form.Flag, 'enabled', _('Enable'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Value, 'port', _('Listening port'),
			_('Leave empty for the ZeroTier default (9993); use 0 for a random port.'));
		o.placeholder = '9993';
		o.validate = function(sectionId, value) {
			if (value && (!/^\d+$/.test(value) || +value > 65535))
				return _('Enter a port from 0 to 65535.');
			return true;
		};

		o = s.option(form.Value, 'local_conf_path', _('local.conf path'),
			_('Optional absolute path to a persistent ZeroTier local.conf file.'));
		o.placeholder = '/etc/zerotier.conf';

		o = s.option(form.Value, 'config_path', _('Persistent state directory'),
			_('Optional persistent directory for moons, controller state and other advanced configuration.'));
		o.placeholder = '/mnt/storage/zerotier';

		o = s.option(form.Flag, 'copy_config_path', _('Copy persistent state to RAM'),
			_('Copy the persistent directory into /var/lib instead of using a symbolic link.'));
		o.default = '0';
		o.rmempty = false;

		s = m.section(form.GridSection, 'network', _('Configured networks'),
			_('Changes take effect after Save & Apply. Network IDs contain exactly 16 hexadecimal characters.'));
		s.anonymous = true;
		s.addremove = true;
		s.sortable = true;

		o = s.option(form.Value, 'id', _('Network ID'));
		o.rmempty = false;
		o.validate = function(sectionId, value) {
			return /^[0-9a-fA-F]{16}$/.test(value || '') ? true :
				_('Enter exactly 16 hexadecimal characters.');
		};

		o = s.option(form.Flag, 'allow_managed', _('Managed routes'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Flag, 'allow_global', _('Global routes'),
			_('Allows managed routes outside private address ranges.'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Flag, 'allow_default', _('Default route'),
			_('Allows ZeroTier to replace the default route. Enable only when intended.'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Flag, 'allow_dns', _('Managed DNS'));
		o.default = '0';
		o.rmempty = false;

		let statusSection = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ text(_('Status')) ]),
			E('table', { 'class': 'table' }, [
				E('tr', {}, [ E('td', {}, [ text(_('Service')) ]), E('td', {}, [
					statusValue('zt-running', status.running ? _('Running') : _('Stopped'), status.running)
				]) ]),
				E('tr', {}, [ E('td', {}, [ text(_('Node')) ]), E('td', {}, [
					statusValue('zt-online', status.online ? _('Online') : _('Offline'), status.online)
				]) ]),
				E('tr', {}, [ E('td', {}, [ text(_('Node ID')) ]), E('td', { 'id': 'zt-node-id' }, [ text(status.node_id) ]) ]),
				E('tr', {}, [ E('td', {}, [ text(_('Version')) ]), E('td', { 'id': 'zt-version' }, [ text(status.version) ]) ]),
				E('tr', {}, [ E('td', {}, [ text(_('PID')) ]), E('td', { 'id': 'zt-pid' }, [ text(status.pid) ]) ]),
				E('tr', {}, [ E('td', {}, [ text(_('Uptime')) ]), E('td', { 'id': 'zt-uptime' }, [ text(formatUptime(status.uptime)) ]) ]),
				E('tr', {}, [ E('td', {}, [ text(_('Identity secret')) ]), E('td', {}, [
					text(configData.identity_secret_present ? _('Present (hidden)') : _('Will be generated on first start'))
				]) ])
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

		let runtimeSection = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ text(_('Runtime networks')) ]),
			E('table', { 'class': 'table' }, [
				E('thead', {}, [ E('tr', {}, [
					E('th', {}, [ text(_('Network ID')) ]),
					E('th', {}, [ text(_('Name')) ]),
					E('th', {}, [ text(_('Status')) ]),
					E('th', {}, [ text(_('Type')) ]),
					E('th', {}, [ text(_('Device')) ]),
					E('th', {}, [ text(_('Addresses')) ]),
					E('th', {}, [ text(_('MAC')) ]),
					E('th', {}, [ text(_('MTU')) ]),
					E('th', {}, [ text(_('Permissions')) ])
				]) ]),
				E('tbody', { 'id': 'zt-runtime-networks' }, networkRows(runtimeNetworks))
			])
		]);

		let packageRunning = !!packageStatus.update_running;
		let packageFailed = packageStatus.update_state == 'error';
		let packageSection = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ text(_('Package updates')) ]),
			E('p', {}, [ text(_('Repository indexes are refreshed once; ZeroTier and this LuCI application are upgraded independently.')) ]),
			E('table', { 'class': 'table' }, [
				E('thead', {}, [ E('tr', {}, [
					E('th', {}, [ text(_('Package')) ]),
					E('th', {}, [ text(_('Installed')) ]),
					E('th', {}, [ text(_('Available')) ]),
					E('th', {}, [ text(_('State')) ]),
					E('th', {}, [ text(_('Action')) ])
				]) ]),
				E('tbody', {}, [
					E('tr', {}, [
						E('td', {}, [ text('zerotier') ]),
						E('td', { 'id': 'zt-zerotier-installed' }, [ text(packageStatus.installed_zerotier) ]),
						E('td', { 'id': 'zt-zerotier-available' }, [ text(packageStatus.available_zerotier) ]),
						E('td', {}, [ E('span', {
							'id': 'zt-zerotier-state',
							'class': packageStatus.zerotier_update_available ? 'label notice' : 'label success'
						}, [ text(packageStateLabel(packageStatus, 'zerotier')) ]) ]),
						E('td', {}, [ E('button', {
							'id': 'zt-zerotier-upgrade',
							'class': 'btn cbi-button cbi-button-apply',
							'disabled': packageRunning || !packageStatus.zerotier_update_available,
							'click': ui.createHandlerFn(this, this.handlePackageAction, 'upgrade_zerotier')
						}, [ text(_('Install ZeroTier update')) ]) ])
					]),
					E('tr', {}, [
						E('td', {}, [ text('luci-app-zt') ]),
						E('td', { 'id': 'zt-luci-installed' }, [ text(packageStatus.installed_luci) ]),
						E('td', { 'id': 'zt-luci-available' }, [ text(packageStatus.available_luci) ]),
						E('td', {}, [ E('span', {
							'id': 'zt-luci-state',
							'class': packageStatus.luci_update_available ? 'label notice' : 'label success'
						}, [ text(packageStateLabel(packageStatus, 'luci')) ]) ]),
						E('td', {}, [ E('button', {
							'id': 'zt-luci-upgrade',
							'class': 'btn cbi-button cbi-button-apply',
							'disabled': packageRunning || !packageStatus.luci_update_available,
							'click': ui.createHandlerFn(this, this.handlePackageAction, 'upgrade_luci')
						}, [ text(_('Install LuCI update')) ]) ])
					])
				])
			]),
			E('p', {}, [ text(_('Operation: ')), E('span', {
				'id': 'zt-package-operation',
				'class': packageRunning ? 'label notice' : (packageFailed ? 'label warning' : 'label success')
			}, [ text(packageRunning ? _('Package operation in progress') :
				(packageFailed ? _('Last package operation failed') : _('Idle'))) ]) ]),
			E('pre', {
				'id': 'zt-package-output',
				'style': (packageFailed && packageStatus.update_output ? '' : 'display:none;') +
					'max-height:12em;overflow:auto;white-space:pre-wrap'
			}, [ text(packageStatus.update_output) ]),
			E('div', { 'class': 'right' }, [ E('button', {
				'id': 'zt-package-check',
				'class': 'btn cbi-button cbi-button-action',
				'disabled': packageRunning,
				'click': ui.createHandlerFn(this, this.handlePackageAction, 'check')
			}, [ text(_('Check for updates')) ]) ])
		]);

		let logSection = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ text(_('Recent log')) ]),
			E('pre', {
				'id': 'zt-log',
				'style': 'max-height:24em;overflow:auto;white-space:pre-wrap'
			}, [ text(logData.log || _('No log entries.')) ])
		]);

		poll.add(function() {
			return Promise.all([ callStatus(), callNetworks(), callLog(), callPackageStatus() ]).then(function(values) {
				updateRuntime(values[0], values[1], values[2]);
				updatePackageStatus(values[3]);
			});
		}, 5);

		return m.render().then(function(formNode) {
			return E('div', {}, [ statusSection, formNode, runtimeSection, packageSection, logSection ]);
		});
	}
});
