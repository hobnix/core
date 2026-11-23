// The declared form block (web/src/shell/genform.js): checks as data, plan arguments, the secret only as stdin.
import { initialValues, fieldError, formArgs, formStdin, formTitle, formReady } from '../web/src/shell/genform.js';

let ok = 0, bad = 0;
const check = (name, cond) => { if (cond) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}`); } };

const block = {
  type: 'form', plan: ['ext/x', 'connect', '--host', '{host}', '--port', '{port}', '--mode', '{mode}', '--tls', '{tls}'], planTitle: 'Connect {host}', stdin: 'token',
  fields: [
    { key: 'host', label: 'Host', type: 'text', required: true, pattern: '^[a-z.]+$', invalid: 'Letters only.' },
    { key: 'port', label: 'Port', type: 'number', min: 1, max: 65535 },
    { key: 'mode', label: 'Mode', type: 'select', options: ['a', 'b'] },
    { key: 'tls', label: 'TLS', type: 'toggle', default: true },
    { key: 'token', label: 'Token', type: 'secret', required: true },
  ],
};
const v0 = initialValues(block);
check('first values: select takes its first option', v0.mode === 'a');
check('first values: a toggle is on or off', v0.tls === 'on');
check('first values: a secret is empty', v0.token === '');
check('required text is refused empty', fieldError(block.fields[0], '') === 'This is needed.');
check('the declared message is used', fieldError(block.fields[0], 'A1') === 'Letters only.');
check('a good pattern passes', fieldError(block.fields[0], 'nas.lan') === '');
check('number below min', fieldError(block.fields[1], '0') !== '');
check('number above max', fieldError(block.fields[1], '70000') !== '');
check('not a number', fieldError(block.fields[1], 'x') !== '');
check('an empty optional number passes', fieldError(block.fields[1], '') === '');
check('a select value outside the options', fieldError(block.fields[2], 'c') !== '');
check('not ready while a required field is empty', !formReady(block, v0) && formArgs(block, v0) === null);
const v = { ...v0, host: ' nas.lan ', port: '22', token: 'S3cret value' };
check('ready when the checks pass', formReady(block, v));
check('plan arguments carry the values, trimmed', JSON.stringify(formArgs(block, v)) === JSON.stringify(['connect', '--host', 'nas.lan', '--port', '22', '--mode', 'a', '--tls', 'on']));
check('the secret is not in the arguments', !JSON.stringify(formArgs(block, v)).includes('S3cret'));
check('the secret is not in the title', !formTitle(block, v).includes('S3cret') && formTitle(block, v) === 'Connect nas.lan');
check('the secret is the one stdin line', formStdin(block, v) === 'S3cret value');
check('a secret template in the plan is empty, never the secret', JSON.stringify(formArgs({ ...block, plan: ['ext/x', '{token}'] }, v)) === JSON.stringify(['']));
check('a newline cannot make a second stdin line', formStdin(block, { ...v, token: 'a\nb' }) === 'ab');
check('no secret field: no stdin', formStdin({ fields: [] }, {}) === undefined);

console.log(`${ok} passed, ${bad} failed`);
process.exit(bad ? 1 : 0);
