// Pure helpers of the declared form block (#473, shell/GenForm.svelte, forms/ops/GenFormDialog.svelte, docs/extensions.md "The form block"). No Svelte here, so a
// test can run them. The checks are the declared ones (required, pattern, min/max, options); the server still checks every argument against the package's changes.
import { planArgs, tpl } from './generic.js';

export const secretField = (block) => (block.fields ?? []).find((f) => f.type === 'secret');

// the first values: a toggle is on/off, a select its default or first option, a secret is always empty (it is never stored or shown back)
export function initialValues(block) {
  const v = {};
  for (const f of block.fields ?? []) {
    if (f.type === 'toggle') v[f.key] = f.default === true ? 'on' : 'off';
    else if (f.type === 'select') v[f.key] = f.options?.includes(f.default) ? f.default : (f.options?.[0] ?? '');
    else if (f.type === 'secret') v[f.key] = '';
    else v[f.key] = f.default === undefined ? '' : String(f.default);
  }
  return v;
}

// '' when the value is fine, else the sentence to show under the field
export function fieldError(f, value) {
  const v = f.type === 'secret' ? String(value ?? '') : String(value ?? '').trim();
  if (f.type === 'toggle') return '';
  if (v === '') return f.required ? 'This is needed.' : '';
  if (f.type === 'select') return f.options?.includes(v) ? '' : 'Choose one of the options.';
  if (f.type === 'number') {
    const n = Number(v);
    if (!Number.isFinite(n)) return 'Enter a number.';
    if (f.min !== undefined && n < f.min) return `At least ${f.min}.`;
    if (f.max !== undefined && n > f.max) return `At most ${f.max}.`;
    return '';
  }
  if (f.pattern) {
    try { if (!new RegExp(f.pattern).test(v)) return f.invalid ?? 'This does not look right.'; } catch { /* a bad pattern was refused at install; the server checks anyway */ }
  }
  return '';
}

export const formReady = (block, values) => (block.fields ?? []).every((f) => !fieldError(f, values[f.key]));

// the values a template may see: never the secret
const visible = (block, values) => {
  const o = {};
  for (const f of block.fields ?? []) if (f.type !== 'secret') o[f.key] = String(values[f.key] ?? '').trim();
  return o;
};

// the plan arguments, or null while the form cannot name a command yet
export const formArgs = (block, values) => (formReady(block, values) ? planArgs(block.plan, visible(block, values)) : null);
export const formTitle = (block, values) => tpl(block.planTitle ?? block.title ?? block.submit ?? 'Change', visible(block, values));

// the one secret as the one line for stdin, or undefined
export const formStdin = (block, values) => {
  const f = secretField(block);
  const s = f ? String(values[f.key] ?? '').replace(/[\r\n]+/g, '').trim() : '';
  return s || undefined;
};
