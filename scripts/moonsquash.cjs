#!/usr/bin/env node
// Host setup only. All format operations execute the compiled MoonBit CLI.
const path = require('node:path');
process.env.MOONSQUASH_CODEC ||= path.join(__dirname, 'codec.py');
process.env.MOONSQUASH_HOST ||= path.join(__dirname, 'host.py');
require('../_build/js/debug/build/cmd/main/main.js');
