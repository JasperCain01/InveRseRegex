// InveRseRegex browser demo.
//
// This file only handles the page: reading inputs, drawing results and
// keeping the URL in step. All the regex work happens in R (see demo.R),
// running in the browser via webR. The page sends its inputs to
// demo_run_json() and draws whatever comes back.

import { WebR } from './webr/webr.js';

// --- Presets ----------------------------------------------------------------
// Each preset is a full page state: examples (a text and one or more wanted
// values) plus any options that differ from the defaults.

const DEFAULT_OPTIONS = {
  generalize: 'compact', flavor: 'pcre', anchor: 'auto', fill: 'skip',
  capture: true, case_sensitive: true,
};

const PRESETS = [
  { name: 'A phone number',
    examples: [{ text: 'Call 555-1234 today', wants: ['555-1234'] }] },
  { name: 'An order reference',
    examples: [{ text: 'order #A1099 shipped', wants: ['A1099'] }] },
  { name: 'Two values from one text',
    examples: [{ text: 'John:42, Jane:37', wants: ['42', '37'] }] },
  { name: 'A name and a year, skipping the middle',
    examples: [{ text: 'Margaret Thatcher was born in 1925.', wants: ['Margaret Thatcher 1925'] }] },
  { name: 'Learning from several examples',
    examples: [
      { text: 'Tony Blair was born in 1953. ', wants: ['Tony Blair 1953'] },
      { text: 'John Major was born in 1943. ', wants: ['John Major 1943'] },
    ] },
  { name: 'A date (with a warning)',
    examples: [{ text: 'Paid 2024-03-15, next due 2024-04-15', wants: ['2024-03-15'] }],
    test: 'Invoices dated 2023-11-30 and 2024-01-02.' },
  { name: 'Base R without perl = TRUE',
    examples: [{ text: 'Ref: AB 1234 (closed)', wants: ['AB 1234'] }],
    options: { flavor: 'posix' } },
];

// --- Small DOM helpers ------------------------------------------------------

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === 'class') node.className = v;
    else if (k === 'text') node.textContent = v;
    else node.setAttribute(k, v);
  }
  for (const c of children) node.append(c);
  return node;
}

function setStatus(kind, text) {
  const s = $('#r-status');
  s.className = `r-status ${kind}`;
  s.textContent = text;
}

// --- Example rows -------------------------------------------------------------

function addWant(exampleNode, value = '') {
  const want = $('#want-template').content.firstElementChild.cloneNode(true);
  $('.ex-want', want).value = value;
  $('.wants', exampleNode).append(want);
  return want;
}

function addExample(text = '', wants = ['']) {
  const node = $('#example-template').content.firstElementChild.cloneNode(true);
  $('.ex-text', node).value = text;
  for (const w of wants) addWant(node, w);
  $('#examples').append(node);
  renumberExamples();
  return node;
}

function renumberExamples() {
  $$('#examples .example').forEach((node, i) => {
    $('.example-title', node).textContent = `Example ${i + 1}`;
  });
}

// The wanted-value box the selection buttons act on: the one last focused in
// this example, or the first.
function activeWant(exampleNode) {
  return $('.ex-want.active', exampleNode) || $('.ex-want', exampleNode);
}

function selectedText(exampleNode) {
  const ta = $('.ex-text', exampleNode);
  return ta.value.slice(ta.selectionStart, ta.selectionEnd);
}

function updateSelectionButtons(exampleNode) {
  const has = selectedText(exampleNode).length > 0;
  for (const b of $$('.selection-actions button', exampleNode)) b.disabled = !has;
}

function wireExamples() {
  const box = $('#examples');

  box.addEventListener('input', schedule);

  // Keep the selection buttons in step with the textarea's selection.
  for (const type of ['select', 'keyup', 'mouseup', 'focusin']) {
    box.addEventListener(type, (e) => {
      const ex = e.target.closest('.example');
      if (ex && e.target.matches('.ex-text')) updateSelectionButtons(ex);
    });
  }
  document.addEventListener('selectionchange', () => {
    const ex = document.activeElement?.closest?.('.example');
    if (ex) updateSelectionButtons(ex);
  });

  box.addEventListener('focusin', (e) => {
    if (!e.target.matches('.ex-want')) return;
    const ex = e.target.closest('.example');
    $$('.ex-want', ex).forEach(w => w.classList.toggle('active', w === e.target));
  });

  // Buttons must not steal focus from the textarea, or the selection is lost.
  box.addEventListener('mousedown', (e) => {
    if (e.target.closest('.selection-actions button')) e.preventDefault();
  });

  box.addEventListener('click', (e) => {
    const ex = e.target.closest('.example');
    if (!ex) return;
    const sel = selectedText(ex);
    if (e.target.matches('.sel-replace') && sel) {
      activeWant(ex).value = sel;
    } else if (e.target.matches('.sel-append') && sel) {
      const w = activeWant(ex);
      w.value = w.value ? `${w.value} ${sel}` : sel;
    } else if (e.target.matches('.sel-new') && sel) {
      const empty = $$('.ex-want', ex).find(w => !w.value);
      if (empty) empty.value = sel; else addWant(ex, sel);
    } else if (e.target.matches('.remove-want')) {
      e.target.closest('.want').remove();
    } else if (e.target.matches('.remove-example')) {
      ex.remove();
      renumberExamples();
    } else {
      return;
    }
    schedule();
  });

  $('#add-example').addEventListener('click', () => {
    const node = addExample();
    $('.ex-text', node).focus();
  });
}

// --- Page state <-> URL ---------------------------------------------------------

function readState() {
  const examples = $$('#examples .example').map(ex => ({
    text: $('.ex-text', ex).value,
    wants: $$('.ex-want', ex).map(w => w.value),
  }));
  return {
    examples,
    options: {
      generalize: $('#opt-generalize').value,
      flavor: $('#opt-flavor').value,
      anchor: $('#opt-anchor').value,
      fill: $('#opt-fill').value,
      capture: $('#opt-capture').checked,
      case_sensitive: $('#opt-case').checked,
    },
    test: $('#test-text').value,
  };
}

function applyState(state) {
  $('#examples').replaceChildren();
  const examples = state.examples?.length ? state.examples : [{ text: '', wants: [''] }];
  for (const ex of examples) addExample(ex.text ?? '', ex.wants?.length ? ex.wants : ['']);
  const o = { ...DEFAULT_OPTIONS, ...(state.options || {}) };
  $('#opt-generalize').value = o.generalize;
  $('#opt-flavor').value = o.flavor;
  $('#opt-anchor').value = o.anchor;
  $('#opt-fill').value = o.fill;
  $('#opt-capture').checked = !!o.capture;
  $('#opt-case').checked = !!o.case_sensitive;
  $('#test-text').value = state.test ?? '';
}

// The state is kept in the URL fragment so a result can be shared or
// bookmarked. The fragment never reaches the server.
function stateToHash(state) {
  return '#' + new URLSearchParams({ s: JSON.stringify(state) }).toString();
}

function stateFromHash(hash) {
  try {
    const s = new URLSearchParams(hash.replace(/^#/, '')).get('s');
    if (!s) return null;
    const state = JSON.parse(s);
    return Array.isArray(state.examples) ? state : null;
  } catch {
    return null;
  }
}

// --- Rendering results ------------------------------------------------------------

// Draw `text` with matches and capture groups highlighted. `spans` come from R
// as UTF-16 offsets, which is exactly how JavaScript indexes strings.
function renderHighlighted(text, spans) {
  const block = el('div', { class: 'hl-block' });
  const cuts = new Set([0, text.length]);
  for (const m of spans) {
    cuts.add(m.start); cuts.add(m.end);
    for (const g of m.groups) if (g) { cuts.add(g.start); cuts.add(g.end); }
  }
  const points = [...cuts].sort((a, b) => a - b);
  for (let i = 0; i < points.length - 1; i++) {
    const a = points[i], b = points[i + 1];
    if (a === b) continue;
    const piece = text.slice(a, b);
    const match = spans.find(m => m.start <= a && b <= m.end);
    if (!match) { block.append(piece); continue; }
    // Innermost (last-opened) group covering this piece, if any.
    let group = 0;
    match.groups.forEach((g, k) => { if (g && g.start <= a && b <= g.end) group = k + 1; });
    const cls = group ? `m g${((group - 1) % 6) + 1}` : 'm';
    const title = group ? `Capture group ${group}` : 'Matched, not captured';
    block.append(el('span', { class: cls, title }, piece));
  }
  return block;
}

function matchCountText(n) {
  if (n === 0) return 'No matches.';
  return n === 1 ? '1 match.' : `${n} matches.`;
}

function renderLegend(nGroups) {
  const legend = $('#legend');
  legend.replaceChildren();
  if (nGroups === 0) return;
  legend.append(el('span', {}, el('span', { class: 'swatch m' }), 'matched, not captured'));
  for (let k = 1; k <= nGroups; k++) {
    legend.append(el('span', {},
      el('span', { class: `swatch g${((k - 1) % 6) + 1}` }), `group ${k}`));
  }
}

function fitText(level) {
  if (level.error) return ['fit-bad', 'error'];
  if (level.missing > 0) return ['fit-bad', `misses ${level.missing}`];
  if (level.extras > 0) return ['fit-warn', `also matches ${level.extras} more`];
  return ['fit-ok', 'exact fit'];
}

function renderResult(res, state) {
  const messages = $('#messages');
  messages.replaceChildren();
  const verdict = $('#verdict');

  if (!res.ok) {
    verdict.className = 'verdict bad';
    verdict.textContent = 'No pattern yet';
    $('#pattern').textContent = ' ';
    $('#r-literal').textContent = ' ';
    messages.append(el('li', { class: 'error', text: res.error }));
    for (const id of ['#highlights', '#test-highlight', '#explain tbody', '#levels tbody', '#snippets', '#legend']) {
      $(id).replaceChildren();
    }
    return;
  }

  $('#pattern').textContent = res.pattern;
  $('#r-literal').textContent = res.r_literal;

  if (res.missing.length) {
    verdict.className = 'verdict bad';
    verdict.textContent = `Misses: ${res.missing.join(', ')}`;
  } else if (res.extras.length) {
    verdict.className = 'verdict warn';
    verdict.textContent = 'Matches what you wanted, and some other text too';
  } else {
    verdict.className = 'verdict ok';
    verdict.textContent = 'Matches what you wanted, and nothing else';
  }
  for (const w of res.warnings) messages.append(el('li', { text: w }));

  // Highlights: one block per distinct text (several wanted values from the
  // same text are sent to R as repeated texts).
  const hl = $('#highlights');
  hl.replaceChildren();
  const seen = new Set();
  let nGroups = 0;
  for (const ex of res.examples) {
    if (seen.has(ex.text)) continue;
    seen.add(ex.text);
    hl.append(renderHighlighted(ex.text, ex.spans));
    hl.append(el('div', { class: 'hl-meta', text: matchCountText(ex.spans.length) }));
    for (const m of ex.spans) nGroups = Math.max(nGroups, m.groups.length);
  }
  renderLegend(nGroups);

  const th = $('#test-highlight');
  th.replaceChildren();
  if (state.test) {
    th.append(renderHighlighted(state.test, res.test));
    th.append(el('div', { class: 'hl-meta', text: matchCountText(res.test.length) }));
  }

  $('#explain tbody').replaceChildren(...res.explain.map(r =>
    el('tr', {}, el('td', {}, el('code', { text: r.token })), el('td', { text: r.meaning }))));

  $('#levels tbody').replaceChildren(...res.levels.map(lv => {
    const [cls, txt] = fitText(lv);
    const row = el('tr', { 'data-level': lv.level, tabindex: '0' },
      el('td', { text: lv.level }),
      el('td', {}, el('code', { text: lv.pattern ?? '' })),
      el('td', { class: cls, text: txt }));
    if (lv.level === state.options.generalize) row.classList.add('current');
    return row;
  }));

  $('#snippets').replaceChildren(...res.snippets.map((s, i) => {
    const id = `snippet-${i}`;
    const block = el('div', { class: 'snippet' },
      el('div', { class: 'code-label', text: s.label }),
      el('div', { class: 'code-row' },
        el('code', { id, text: s.code }),
        el('button', { type: 'button', class: 'copy small', 'data-copy-target': id }, 'Copy')));
    if (s.note) block.append(el('div', { class: 'note', text: s.note }));
    return block;
  }));
}

// --- Talking to R ------------------------------------------------------------------

let webR = null;
const RUN_TIMEOUT_MS = 15000;

async function startR() {
  setStatus('loading', 'Starting R…');
  webR = new WebR({ baseUrl: new URL('./webr/', location.href).href, interactive: false });
  await webR.init();
  setStatus('loading', 'Loading InveRseRegex…');
  const [pkg, glue] = await Promise.all(['pkg/InveRseRegex.tar.gz', 'demo.R'].map(async (url) => {
    const r = await fetch(url);
    if (!r.ok) throw new Error(`Could not download ${url} (${r.status})`);
    return new Uint8Array(await r.arrayBuffer());
  }));
  await webR.FS.writeFile('/tmp/InveRseRegex.tar.gz', pkg);
  await webR.FS.writeFile('/tmp/demo.R', glue);
  await webR.evalRVoid(`
    lib <- "/tmp/rlib"
    dir.create(lib, showWarnings = FALSE)
    untar("/tmp/InveRseRegex.tar.gz", exdir = lib, tar = "internal")
    .libPaths(c(lib, .libPaths()))
    library(InveRseRegex)
    source("/tmp/demo.R")
  `);
  setStatus('ready', 'R ready');
}

// Flatten the examples into the parallel text / want vectors regexify() takes.
// Several wanted values from one text become repeated texts, which the package
// treats exactly like one shared text.
function toArgs(state) {
  const text = [], want = [];
  for (const ex of state.examples) {
    for (const w of ex.wants) {
      if (w === '') continue;
      text.push(ex.text);
      want.push(w);
    }
  }
  return { text, want };
}

async function callR(state) {
  const { text, want } = toArgs(state);
  if (text.length === 0) {
    return { ok: false, error: 'Enter some text and the part of it you want.' };
  }
  const o = state.options;
  const env = {
    text, want, test_text: state.test,
    generalize: o.generalize, flavor: o.flavor, anchor: o.anchor, fill: o.fill,
    capture: o.capture, case_sensitive: o.case_sensitive,
  };
  const call = webR.evalRString(
    'demo_run_json(text, want, generalize, flavor, capture, anchor, case_sensitive, fill, test_text)',
    { env });
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error('timeout')), RUN_TIMEOUT_MS);
  });
  try {
    return JSON.parse(await Promise.race([call, timeout]));
  } finally {
    clearTimeout(timer);
  }
}

// Runs are debounced while typing, and never overlap: if inputs change while
// R is busy, one more run happens afterwards with the latest state.
let debounce = null, running = false, rerun = false, ready = false;

function schedule() {
  clearTimeout(debounce);
  debounce = setTimeout(run, 250);
}

async function run() {
  if (!ready) return;
  if (running) { rerun = true; return; }
  running = true;
  try {
    do {
      rerun = false;
      const state = readState();
      history.replaceState(null, '', stateToHash(state));
      $('.outputs').classList.add('stale');
      setStatus('busy', 'Working…');
      try {
        renderResult(await callR(state), state);
        setStatus('ready', 'R ready');
      } catch (err) {
        if (err.message === 'timeout') {
          // R cannot be interrupted on this kind of hosting, so start afresh.
          ready = false;
          renderResult({ ok: false, error: 'That took too long, so R was restarted. Try a stricter option or shorter text.' }, state);
          webR.close();
          await startR();
          ready = true;
        } else {
          setStatus('error', 'R error');
          renderResult({ ok: false, error: String(err.message || err) }, state);
        }
      } finally {
        $('.outputs').classList.remove('stale');
      }
    } while (rerun);
  } finally {
    running = false;
  }
}

// --- Other controls ------------------------------------------------------------------

async function copyText(text, button) {
  try {
    await navigator.clipboard.writeText(text);
    const old = button.textContent;
    button.textContent = 'Copied';
    setTimeout(() => { button.textContent = old; }, 1200);
  } catch {
    button.textContent = 'Copy failed';
  }
}

function wireControls() {
  for (const id of ['#opt-generalize', '#opt-flavor', '#opt-anchor', '#opt-fill', '#opt-capture', '#opt-case']) {
    $(id).addEventListener('change', schedule);
  }
  $('#test-text').addEventListener('input', schedule);

  const preset = $('#preset');
  PRESETS.forEach((p, i) => preset.append(el('option', { value: String(i) }, p.name)));
  preset.addEventListener('change', () => {
    const p = PRESETS[Number(preset.value)];
    if (!p) return;
    applyState({ examples: p.examples, options: p.options, test: p.test });
    preset.value = '';
    schedule();
  });

  const pickLevel = (row) => {
    if (!row?.dataset.level) return;
    $('#opt-generalize').value = row.dataset.level;
    schedule();
  };
  $('#levels').addEventListener('click', (e) => pickLevel(e.target.closest('tr')));
  $('#levels').addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); pickLevel(e.target.closest('tr')); }
  });

  document.addEventListener('click', (e) => {
    const target = e.target.closest('[data-copy-target]');
    if (target) copyText($(`#${target.dataset.copyTarget}`).textContent, target);
  });
  $('#share').addEventListener('click', (e) => copyText(location.href, e.target));
}

async function showBuildInfo() {
  try {
    const info = await (await fetch('build-info.json')).json();
    $('#build-info').textContent =
      `InveRseRegex ${info.package_version} (commit ${info.commit}), webR ${info.webr_version}.`;
  } catch { /* not essential */ }
}

// --- Start up --------------------------------------------------------------------------

wireExamples();
wireControls();
applyState(stateFromHash(location.hash) || { examples: PRESETS[0].examples });
showBuildInfo();

try {
  await startR();
  ready = true;
  run();
} catch (err) {
  setStatus('error', 'R failed to start');
  renderResult({ ok: false, error: `R could not be started in this browser: ${err.message || err}` }, readState());
}
