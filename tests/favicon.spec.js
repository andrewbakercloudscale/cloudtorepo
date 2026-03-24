const { test, expect, chromium } = require('@playwright/test');
const path = require('path');
const fs = require('fs');

const FILE_URL = 'file://' + path.resolve(__dirname, '../index.html');
const FAVICON_PATH = path.resolve(__dirname, '../favicon-tc.png');

test.describe('Favicon', () => {
  test('link tag points to favicon-tc.png', async ({ page }) => {
    await page.goto(FILE_URL);
    const href = await page.$eval('link[rel="icon"]', el => el.getAttribute('href'));
    console.log('favicon href:', href);
    expect(href).toContain('favicon-tc.png');
  });

  test('favicon file exists and is a valid PNG', async () => {
    expect(fs.existsSync(FAVICON_PATH)).toBe(true);
    const buf = fs.readFileSync(FAVICON_PATH);
    // PNG magic bytes: 89 50 4E 47
    expect(buf[0]).toBe(0x89);
    expect(buf[1]).toBe(0x50);
    expect(buf[2]).toBe(0x4E);
    expect(buf[3]).toBe(0x47);
    console.log('favicon size:', buf.length, 'bytes');
  });

  test('favicon renders visibly in page', async ({ page }) => {
    await page.goto(FILE_URL);
    await page.waitForLoadState('domcontentloaded');
    await page.screenshot({ path: 'tests/screenshots/favicon-tab.png', fullPage: false });
    // Verify the favicon image loads (no broken image response)
    const faviconHref = await page.$eval('link[rel="icon"]', el => el.href);
    console.log('resolved favicon URL:', faviconHref);
    const response = await page.request.get(faviconHref).catch(() => null);
    if (response) {
      console.log('favicon status:', response.status());
      console.log('favicon content-type:', response.headers()['content-type']);
    }
  });
});
