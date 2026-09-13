#!/usr/bin/env ucode
// SPDX-License-Identifier: MIT

'use strict';

import { access, popen, readfile, writefile } from 'fs';
import { cursor } from 'uci';
import { init_action, init_enabled, process_list } from 'luci.sys';

const HEALTH_FILE = '/var/run/newt/healthy';
const NEWT_BIN = '/usr/bin/newt';
const APK_BIN = '/usr/bin/apk';
const PACKAGE_NAMES = [ 'pangolin-newt', 'luci-app-pangolin-newt' ];
const UPDATE_SERVICE = 'pangolin-newt-update';
const UPDATE_ACTION_FILE = '/var/run/pangolin-newt-update.action';
const UPDATE_STATE_FILE = '/var/run/pangolin-newt-update.state';
const UPDATE_EXIT_FILE = '/var/run/pangolin-newt-update.exit';
const UPDATE_LOG_FILE = '/var/run/pangolin-newt-update.log';
const UPDATE_LOCK_DIR = '/var/lock/pangolin-newt-update.lock';
const uci = cursor();

function runCommand(command) {
	let pipe = popen(`${command} 2>&1`, 'r');
	if (!pipe)
		return { success: false, exit_code: -1, output: 'Unable to start command' };

	let output = pipe.read('all') || '';
	let exitCode = pipe.close();

	return {
		success: exitCode === 0,
		exit_code: exitCode,
		output: substr(output, 0, 65536)
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
		installed_newt: installed['pangolin-newt'] || null,
		available_newt: available['pangolin-newt'] || null,
		installed_luci: installed['luci-app-pangolin-newt'] || null,
		available_luci: available['luci-app-pangolin-newt'] || null,
		update_available: !!upgradable['pangolin-newt'] ||
			!!upgradable['luci-app-pangolin-newt'],
		update_state: updateState,
		update_running: updateState == 'queued' || updateState == 'running' || !!access(UPDATE_LOCK_DIR),
		update_exit_code: updateExit ? +updateExit : null,
		update_output: substr(updateOutput, 0, 8192)
	};
}

function getProcess() {
	for (let proc in process_list()) {
		if (match(proc.COMMAND, /(^|\/)newt( |$)/))
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

	// Linux exposes /proc/<pid>/stat start time in USER_HZ, fixed at 100.
	return max(0, int(uptimeSeconds - startTicks / 100));
}

function getVersion() {
	if (!access(NEWT_BIN))
		return null;

	let pipe = popen('/usr/bin/newt --version 2>&1', 'r');
	if (!pipe)
		return null;

	let output = trim(pipe.read('all') || '');
	pipe.close();

	return output || null;
}

function getLog() {
	let pipe = popen('/sbin/logread -e newt 2>/dev/null | /usr/bin/tail -n 50', 'r');
	if (!pipe)
		return '';

	let output = pipe.read('all') || '';
	pipe.close();

	// Defense in depth: even if upstream logging changes, redact the configured
	// credential before returning text to the browser.
	uci.load('newt');
	let secret = uci.get('newt', 'main', 'secret') || '';
	uci.unload();
	if (secret)
		output = join('[redacted]', split(output, secret));

	return substr(output, 0, 65536);
}

const methods = {
	get_status: {
		call: function() {
			let proc = getProcess();

			return {
				running: !!proc,
				connected: !!proc && !!access(HEALTH_FILE),
				pid: proc ? +proc.PID : null,
				uptime: proc ? getProcessUptime(proc.PID) : null,
				boot_enabled: init_enabled('newt'),
				version: getVersion()
			};
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

			let result = init_action('newt', action);
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

			if (index([ 'check', 'upgrade' ], action) < 0)
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

return { 'luci.pangolin-newt': methods };
