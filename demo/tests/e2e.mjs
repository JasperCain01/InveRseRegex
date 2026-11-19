// End-to-end smoke test of the built site in a real (headless) browser.
//
// Catches what the R tests cannot: a broken webR build, wrong asset paths, the
// page failing to start R, or the browser and R disagreeing about where a
// match is. Run `npm run build` first. Exits non-zero on the first failure.
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { serve } from '../scripts/serve.mjs';

const DEMO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const server = await serve(path.join(DEMO, '_site'));
const base = `http://127.0.0.1:${server.address().port}/`;
const browser = await chromium.launch();

const errors = [];
async function openPage(url = base) {
  const page = await browser.newPage();
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(url);
  await settle(page, 120000); // first start includes loading R
  return page;
}

// Wait until R is ready and no run is in progress or pending.
async function settle(page, timeout = 30000) {
  await page.waitForTimeout(350); // longer than the input debounce
  await page.waitForFunction(() =>
    document.querySelector('#r-status').classList.contains('ready') &&
    !document.querySelector('.outputs').classList.contains('stale'), null, { timeout });
}

async function fill(page, selector, value) {
  await page.fill(selector, value);
  await settle(page);
}

const pattern = (page) => page.textContent('#pattern');
const highlighted = (page, root = '#highlights') =>
  page.$$eval(`${root} .m`, (els) => els.map((e) => e.textContent));

const tests = {
  async 'starts R and shows the default example'() {
    const page = await openPage();
    assert.equal(await pattern(page), '\\b(\\d{3}-\\d{4})\\b');
    assert.equal(await page.textContent('#r-literal'), '"\\\\b(\\\\d{3}-\\\\d{4})\\\\b"');
    assert.deepEqual(await highlighted(page), ['555-1234']);
    assert.match(await page.textContent('#verdict'), /nothing else/);
    assert.equal(await page.$$eval('#explain tbody tr', (r) => r.length), 7);
    assert.equal(await page.$$eval('#levels tbody tr', (r) => r.length), 4);
    await page.close();
  },

  async 'selected text becomes the wanted value'() {
    const page = await openPage();
    await fill(page, '.ex-text', 'Invoice INV-0042 paid');
    await page.$eval('.ex-text', (ta) => { ta.focus(); ta.setSelectionRange(8, 16); });
    await page.dispatchEvent('.ex-text', 'select');
    await page.click('.sel-replace');
    await settle(page);
    assert.equal(await page.inputValue('.ex-want'), 'INV-0042');
    assert.equal(await pattern(page), '\\b([A-Z]{3}-\\d{4})\\b');
    await page.close();
  },

  async 'highlights line up after emoji'() {
    const page = await openPage();
    await fill(page, '.ex-text', '\u{1F600} x 42 \u{1F680}\u{1F680} y 7');
    await fill(page, '.ex-want', '42');
    assert.deepEqual(await highlighted(page), ['42']);
    await fill(page, '#test-text', '\u{1F600}\u{1F600} 13 and 99');
    assert.deepEqual(await highlighted(page, '#test-highlight'), ['13', '99']);
    await page.close();
  },

  async 'capture groups are coloured separately'() {
    const page = await openPage();
    await page.selectOption('#preset', { label: 'A name and a year, skipping the middle' });
    await settle(page);
    const groups = await page.$$eval('#highlights .m', (els) =>
      els.map((e) => [e.className, e.textContent]));
    assert.deepEqual(groups, [
      ['m g1', 'Margaret Thatcher '],
      ['m', 'was born in '],
      ['m g2', '1925'],
    ]);
    await page.close();
  },

  async 'choosing a level in the table switches to it'() {
    const page = await openPage();
    await page.click('#levels tr[data-level="loose"]');
    await settle(page);
    assert.equal(await page.inputValue('#opt-generalize'), 'loose');
    assert.equal(await pattern(page), '\\b(\\d+-\\d+)\\b');
    await page.close();
  },

  async 'the URL restores the full state'() {
    const page = await openPage();
    await page.selectOption('#preset', { label: 'Learning from several examples' });
    await settle(page);
    await page.selectOption('#opt-flavor', 'posix');
    await fill(page, '#test-text', 'Gordon Brown was born in 1951.');
    const url = page.url();
    const expected = await pattern(page);
    await page.close();

    const again = await openPage(url);
    assert.equal(await again.$$eval('.ex-text', (t) => t.length), 2);
    assert.equal(await again.inputValue('#opt-flavor'), 'posix');
    assert.equal(await again.inputValue('#test-text'), 'Gordon Brown was born in 1951.');
    assert.equal(await pattern(again), expected);
    await again.close();
  },

  async 'bad input shows a message rather than failing'() {
    const page = await openPage();
    await fill(page, '.ex-want', '');
    assert.match(await page.textContent('#messages'), /Enter some text/);
    await page.close();
  },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
  try {
    await fn();
    console.log(`ok   ${name}`);
  } catch (err) {
    failed++;
    console.log(`FAIL ${name}\n     ${String(err.message).split('\n').join('\n     ')}`);
  }
}
if (errors.length) {
  failed++;
  console.log(`FAIL uncaught page errors:\n     ${errors.join('\n     ')}`);
}

await browser.close();
server.close();
console.log(failed ? `\n${failed} failed` : '\nall passed');
process.exit(failed ? 1 : 0);
