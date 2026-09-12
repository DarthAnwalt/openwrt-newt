#!/usr/bin/env ucode
// SPDX-License-Identifier: MIT

'use strict';

import { access, popen, readfile } from 'fs';
import { cursor } from 'uci';
import { init_action, init_enabled, process_list } from 'luci.sys';

const HEALTH_FILE = '/var/run/newt/healthy';
const NEWT_BIN = '/usr/bin/newt';
const uci = cursor();

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
	}
};

return { 'luci.pangolin-newt': methods };
