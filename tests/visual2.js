const { chromium } = require('@playwright/test');
const path = require('path');
const FILE_URL = 'file://' + path.resolve(__dirname, '../index.html');

(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  await page.goto(FILE_URL);

  // Screenshot during matrix
  await page.waitForTimeout(500);
  await page.screenshot({ path: 'tests/screenshots/a-matrix-active.png' });

  // Wait for matrix to fully fade (2.5s + 1s fade = 3.5s)
  await page.waitForTimeout(3500);
  await page.screenshot({ path: 'tests/screenshots/b-page-clean.png' });

  // Hover terminal
  await page.locator('.terminal-wrap').scrollIntoViewIfNeeded();
  await page.waitForTimeout(200);
  await page.screenshot({ path: 'tests/screenshots/c-terminal-before.png' });
  await page.locator('.terminal-wrap').hover();
  await page.waitForTimeout(400);
  await page.screenshot({ path: 'tests/screenshots/d-terminal-hover.png' });

  await browser.close();
  console.log('Done');
})();
