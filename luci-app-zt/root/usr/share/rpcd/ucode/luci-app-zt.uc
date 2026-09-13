#!/usr/bin/env ucode
// SPDX-License-Identifier: MIT

'use strict';

import { access, popen, readfile, writefile } from 'fs';
import { cursor } from 'uci';
import { init_action, init_enabled, process_list } from 'luci.sys';

const ZEROTIER_CLI = '/usr/bin/zerotier-cli';
const APK_BIN = '/usr/bin/apk';
const PACKAGE_NAMES = [ 'zerotier', 'luci-app-zt' ];
const UPDATE_SERVICE = 'luci-app-zt-update';
const UPDATE_ACTION_FILE = '/var/run/luci-app-zt-update.action';
const UPDATE_STATE_FILE = '/var/run/luci-app-zt-update.state';
const UPDATE_EXIT_FILE = '/var/run/luci-app-zt-update.exit';
const UPDATE_LOG_FILE = '/var/run/luci-app-zt-update.log';
const UPDATE_LOCK_DIR = '/var/lock/luci-app-zt-update.lock';
const uci = cursor();

function runCommand(command, limit) {
	let pipe = popen(`${command} 2>&1`, 'r');
	if (!pipe)
		return { success: false, exit_code: -1, output: 'Unable to start command' };

	let output = pipe.read('all') || '';
	let exitCode = pipe.close();

	return {
		success: exitCode === 0,
		exit_code: exitCode,
		output: substr(output, 0, limit || 65536)
	};
}

function queryPackageVersions(source, upgradable) {
	let filter = upgradable ? ' --upgradable' : '';
	let command = `${APK_BIN} query --from ${source}${filter}` +
		` --fields name,version --format json ${join(' ', PACKAGE_NAMES)}`;
	let result = runCommand(command);
	let versions = {};

	if (!result.success)
		return versions;

	try {
		let packages = json(result.output);
		for (let pkg in packages)
			if (index(PACKAGE_NAMES, pkg?.name) >= 0 && type(pkg?.version) == 'string')
				versions[pkg.name] = pkg.version;
	}
	catch (err) {
		return {};
	}

	return versions;
}

function getPackageStatus() {
	let installed = queryPackageVersions('installed', false);
	let available = queryPackageVersions('repositories', false);
	let upgradable = queryPackageVersions('system', true);
	let updateState = trim(readfile(UPDATE_STATE_FILE) || 'idle');
	let updateExit = trim(readfile(UPDATE_EXIT_FILE) || '');
	let updateOutput = readfile(UPDATE_LOG_FILE) || '';

	return {
		installed_zerotier: installed.zerotier || null,
		available_zerotier: available.zerotier || null,
		installed_luci: installed['luci-app-zt'] || null,
		available_luci: available['luci-app-zt'] || null,
		zerotier_update_available: !!upgradable.zerotier,
		luci_update_available: !!upgradable['luci-app-zt'],
		update_state: updateState,
		update_running: updateState == 'queued' || updateState == 'running' || !!access(UPDATE_LOCK_DIR),
		update_exit_code: updateExit ? +updateExit : null,
		update_output: substr(updateOutput, 0, 8192)
	};
}

function getConfig() {
	let global = {
		enabled: '0',
		port: '',
		local_conf_path: '',
		config_path: '',
		copy_config_path: '0'
	};
	let networks = [];

	uci.load('zerotier');
	global.enabled = uci.get('zerotier', 'global', 'enabled') || '0';
	global.port = uci.get('zerotier', 'global', 'port') || '';
	global.local_conf_path = uci.get('zerotier', 'global', 'local_conf_path') || '';
	global.config_path = uci.get('zerotier', 'global', 'config_path') || '';
	global.copy_config_path = uci.get('zerotier', 'global', 'copy_config_path') || '0';
	let secretPresent = !!uci.get('zerotier', 'global', 'secret');

	uci.foreach('zerotier', 'network', (section) => {
		push(networks, {
			'.name': section['.name'],
			id: section.id || '',
			allow_managed: section.allow_managed || '1',
			allow_global: section.allow_global || '0',
			allow_default: section.allow_default || '0',
			allow_dns: section.allow_dns || '0'
		});
	});
	uci.unload();

	return {
		config: { global: global, network: networks },
		identity_secret_present: secretPresent
	};
}

function validFlag(value) {
	return value == '0' || value == '1';
}

function validPath(value) {
	return value == '' ||
		(!!match(value, /^\/[A-Za-z0-9_.\/-]+$/) && !match(value, /(^|\/)\.\.(\/|$)/));
}

function setOptional(config, section, option, value) {
	if (value == null || value == '')
		uci.delete(config, section, option);
	else
		uci.set(config, section, option, value);
}

function setConfig(config) {
	let global = config?.global;
	let networks = config?.networks;

	if (type(global) != 'object' || type(networks) != 'array')
		return { success: false, error: 'Invalid configuration document' };
	if (!validFlag(global.enabled) || !validFlag(global.copy_config_path))
		return { success: false, error: 'Invalid boolean option' };
	if (global.port != '' && (!match(global.port, /^[0-9]+$/) || +global.port > 65535))
		return { success: false, error: 'Port must be between 0 and 65535' };
	if (!validPath(global.local_conf_path || '') || !validPath(global.config_path || ''))
		return { success: false, error: 'Configuration paths must be safe absolute paths' };
	if (length(networks) > 64)
		return { success: false, error: 'At most 64 networks may be configured' };

	let seen = {};
	for (let network in networks) {
		let id = lc(network?.id || '');
		if (!match(id, /^[0-9a-f]{16}$/))
			return { success: false, error: 'Every network ID must contain exactly 16 hexadecimal characters' };
		if (seen[id])
			return { success: false, error: 'Duplicate network ID' };
		seen[id] = true;
		for (let option in [ 'allow_managed', 'allow_global', 'allow_default', 'allow_dns' ])
			if (!validFlag(network?.[option] || '0'))
				return { success: false, error: 'Invalid network option' };
	}

	uci.load('zerotier');
	if (!uci.get('zerotier', 'global'))
		uci.set('zerotier', 'global', 'zerotier');
	uci.set('zerotier', 'global', 'enabled', global.enabled);
	setOptional('zerotier', 'global', 'port', global.port || '');
	setOptional('zerotier', 'global', 'local_conf_path', global.local_conf_path || '');
	setOptional('zerotier', 'global', 'config_path', global.config_path || '');
	uci.set('zerotier', 'global', 'copy_config_path', global.copy_config_path);

	let oldSections = [];
	uci.foreach('zerotier', 'network', (section) => push(oldSections, section['.name']));
	for (let section in oldSections)
		uci.delete('zerotier', section);

	for (let network in networks) {
		let section = uci.add('zerotier', 'network');
		uci.set('zerotier', section, 'id', lc(network.id));
		uci.set('zerotier', section, 'allow_managed', network.allow_managed || '1');
		uci.set('zerotier', section, 'allow_global', network.allow_global || '0');
		uci.set('zerotier', section, 'allow_default', network.allow_default || '0');
		uci.set('zerotier', section, 'allow_dns', network.allow_dns || '0');
	}

	uci.commit('zerotier');
	uci.unload();
	return { success: true };
}

function getProcess() {
	for (let proc in process_list()) {
		if (match(proc.COMMAND, /(^|\/)zerotier-one( |$)/))
			return proc;
	}

	return null;
}

function getProcessUptime(pid) {
	let processStat = readfile(`/proc/${pid}/stat`);
	let systemUptime = readfile('/proc/uptime');

	if (!processStat || !systemUptime)
		return null;

	let fields = split(trim(processStat), / +/);
	let uptimeFields = split(trim(systemUptime), / +/);
	let startTicks = +fields[21];
	let uptimeSeconds = +uptimeFields[0];

	if (!startTicks || !uptimeSeconds)
		return null;

	return max(0, int(uptimeSeconds - startTicks / 100));
}

function getInfo() {
	if (!access(ZEROTIER_CLI))
		return {};

	let result = runCommand('/usr/bin/zerotier-cli -j info', 32768);
	if (!result.success)
		return {};

	try {
		return json(result.output) || {};
	}
	catch (err) {
		return {};
	}
}

function getNetworks() {
	if (!access(ZEROTIER_CLI))
		return { success: false, networks: [], error: 'zerotier-cli is not installed' };

	let result = runCommand('/usr/bin/zerotier-cli -j listnetworks', 131072);
	if (!result.success)
		return { success: false, networks: [], error: substr(result.output, 0, 1024) };

	try {
		let raw = json(result.output);
		let networks = [];

		for (let network in raw) {
			push(networks, {
				id: network?.id || network?.nwid || null,
				name: network?.name || null,
				status: network?.status || null,
				type: network?.type || null,
				device: network?.portDeviceName || null,
				mac: network?.mac || null,
				mtu: network?.mtu || null,
				assigned_addresses: type(network?.assignedAddresses) == 'array' ? network.assignedAddresses : [],
				allow_managed: !!network?.allowManaged,
				allow_global: !!network?.allowGlobal,
				allow_default: !!network?.allowDefault,
				allow_dns: !!network?.allowDNS
			});
		}

		return { success: true, networks: networks };
	}
	catch (err) {
		return { success: false, networks: [], error: 'Unable to parse zerotier-cli JSON output' };
	}
}

function getLog() {
	let result = runCommand('/sbin/logread -e zerotier | /usr/bin/tail -n 50');
	let output = result.output || '';

	// Never return the identity secret to the browser, even if a future daemon
	// or init-script version happens to log it.
	uci.load('zerotier');
	let secret = uci.get('zerotier', 'global', 'secret') || '';
	uci.unload();
	if (secret)
		output = join('[redacted]', split(output, secret));

	return substr(output, 0, 65536);
}

const methods = {
	get_config: {
		call: function() {
			return getConfig();
		}
	},

	set_config: {
		args: { config: {} },
		call: function(request) {
			return setConfig(request?.args?.config || {});
		}
	},

	get_status: {
		call: function() {
			let proc = getProcess();
			let info = getInfo();

			return {
				running: !!proc,
				online: !!proc && !!info?.online,
				pid: proc ? +proc.PID : null,
				uptime: proc ? getProcessUptime(proc.PID) : null,
				boot_enabled: init_enabled('zerotier'),
				version: info?.version || null,
				node_id: info?.address || null
			};
		}
	},

	get_networks: {
		call: function() {
			return getNetworks();
		}
	},

	get_log: {
		call: function() {
			return { log: getLog() };
		}
	},

	get_package_status: {
		call: function() {
			return getPackageStatus();
		}
	},

	service_action: {
		args: { action: 'action' },
		call: function(request) {
			let action = request?.args?.action || '';
			if (index([ 'start', 'stop', 'restart' ], action) < 0)
				return { success: false, error: 'Invalid service action' };

			let result = init_action('zerotier', action);
			return {
				success: result === 0,
				action: action,
				exit_code: result
			};
		}
	},

	package_action: {
		args: { action: 'action' },
		call: function(request) {
			let action = request?.args?.action || '';

			if (index([ 'check', 'upgrade_zerotier', 'upgrade_luci' ], action) < 0)
				return { success: false, error: 'Invalid package action' };

			let current = getPackageStatus();
			if (current.update_running)
				return { success: false, error: 'A package operation is already running', status: current };

			try {
				writefile(UPDATE_ACTION_FILE, `${action}\n`);
				writefile(UPDATE_STATE_FILE, 'queued\n');
				writefile(UPDATE_EXIT_FILE, '');
			}
			catch (err) {
				return { success: false, error: `Unable to queue package action: ${err}` };
			}

			let result = init_action(UPDATE_SERVICE, 'start');
			if (result !== 0) {
				writefile(UPDATE_STATE_FILE, 'error\n');
				return { success: false, error: 'Unable to start the package update service' };
			}

			return { success: true, queued: true, status: getPackageStatus() };
		}
	}
};

return { 'luci.zt': methods };
