const { test, expect, chromium } = require('@playwright/test');
const path = require('path');

const FILE_URL = 'file://' + path.resolve(__dirname, '../index.html');

test.describe('Hover pop effects', () => {
  test.beforeEach(async ({ page }) => {
    // Clear sessionStorage so matrix rain always shows fresh
    await page.addInitScript(() => sessionStorage.clear());
    await page.goto(FILE_URL);
    await page.waitForLoadState('domcontentloaded');
  });

  test('terminal-wrap jumps on hover', async ({ page }) => {
    const el = page.locator('.terminal-wrap');
    const before = await el.evaluate(e => getComputedStyle(e).transform);
    await el.hover();
    await page.waitForTimeout(300); // let transition complete
    const after = await el.evaluate(e => getComputedStyle(e).transform);
    await page.screenshot({ path: 'tests/screenshots/terminal-hover.png', fullPage: false });
    expect(after).not.toBe(before);
    expect(after).not.toBe('none');
    console.log('terminal-wrap before:', before);
    console.log('terminal-wrap after: ', after);
  });

  test('hero-logo jumps on hover', async ({ page }) => {
    const el = page.locator('.hero-logo');
    const before = await el.evaluate(e => getComputedStyle(e).transform);
    await el.hover();
    await page.waitForTimeout(300);
    const after = await el.evaluate(e => getComputedStyle(e).transform);
    await page.screenshot({ path: 'tests/screenshots/logo-hover.png', fullPage: false });
    expect(after).not.toBe(before);
    expect(after).not.toBe('none');
    console.log('hero-logo before:', before);
    console.log('hero-logo after: ', after);
  });

  test('badge jumps on hover', async ({ page }) => {
    const el = page.locator('.badge');
    const before = await el.evaluate(e => getComputedStyle(e).transform);
    await el.hover();
    await page.waitForTimeout(300);
    const after = await el.evaluate(e => getComputedStyle(e).transform);
    await page.screenshot({ path: 'tests/screenshots/badge-hover.png', fullPage: false });
    expect(after).not.toBe(before);
    expect(after).not.toBe('none');
    console.log('badge before:', before);
    console.log('badge after: ', after);
  });

  test('matrix canvas appears on first load', async ({ page }) => {
    // Matrix overlay should exist briefly on fresh load
    const overlay = page.locator('#matrix-overlay');
    await expect(overlay).toBeAttached();
    await page.screenshot({ path: 'tests/screenshots/matrix-rain.png', fullPage: false });
  });

  test('matrix canvas does not appear on second load', async ({ page }) => {
    // Simulate second visit (sessionStorage already set)
    await page.addInitScript(() => sessionStorage.setItem('tc_matrix', '1'));
    await page.goto(FILE_URL);
    await page.waitForLoadState('domcontentloaded');
    const overlay = page.locator('#matrix-overlay');
    await expect(overlay).not.toBeAttached();
  });
});
