const { chromium } = require('@playwright/test');
const path = require('path');

const FILE_URL = 'file://' + path.resolve(__dirname, '../index.html');

(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await ctx.newPage();

  // Fresh session — matrix should show
  await page.goto(FILE_URL);
  await page.waitForTimeout(200);
  await page.screenshot({ path: 'tests/screenshots/01-initial.png' });
  console.log('01-initial.png — page on load (matrix should be visible)');

  await page.waitForTimeout(1500);
  await page.screenshot({ path: 'tests/screenshots/02-mid-matrix.png' });
  console.log('02-mid-matrix.png — mid matrix animation');

  // Check matrix overlay
  const matrixEl = await page.$('#matrix-overlay');
  console.log('matrix-overlay in DOM:', !!matrixEl);

  // Hover terminal
  const terminal = page.locator('.terminal-wrap');
  const termBox = await terminal.boundingBox();
  console.log('terminal boundingBox:', termBox);
  await page.screenshot({ path: 'tests/screenshots/03-before-terminal-hover.png' });
  await terminal.hover();
  await page.waitForTimeout(400);
  await page.screenshot({ path: 'tests/screenshots/04-after-terminal-hover.png' });
  const termTransform = await terminal.evaluate(e => getComputedStyle(e).transform);
  console.log('terminal transform on hover:', termTransform);

  // Hover logo
  const logo = page.locator('.hero-logo');
  await logo.hover();
  await page.waitForTimeout(400);
  await page.screenshot({ path: 'tests/screenshots/05-after-logo-hover.png' });
  const logoTransform = await logo.evaluate(e => getComputedStyle(e).transform);
  console.log('logo transform on hover:', logoTransform);

  // Check body overflow
  const bodyOverflow = await page.evaluate(() => {
    const s = getComputedStyle(document.body);
    return { overflowX: s.overflowX, overflowY: s.overflowY };
  });
  console.log('body computed overflow:', bodyOverflow);

  const heroOverflow = await page.evaluate(() => {
    const s = getComputedStyle(document.querySelector('.hero'));
    return { overflowX: s.overflowX, overflowY: s.overflowY };
  });
  console.log('.hero computed overflow:', heroOverflow);

  await browser.close();
  console.log('Done — check tests/screenshots/');
})();
