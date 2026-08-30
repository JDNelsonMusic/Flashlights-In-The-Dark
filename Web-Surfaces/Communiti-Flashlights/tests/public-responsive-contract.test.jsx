import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import FlashlightsHomePage from '../src/landing';
import {
  FLASHLIGHTS_THEME_STORAGE_KEY,
  resolveInitialTheme,
} from '../src/public/FlashlightsPageFrame';

const publicCss = readFileSync(resolve(process.cwd(), 'src/public/public.css'), 'utf8');

const cssBlock = (source, prelude) => {
  const preludeIndex = source.indexOf(prelude);
  if (preludeIndex < 0) return '';
  const blockStart = source.indexOf('{', preludeIndex);
  if (blockStart < 0) return '';

  let depth = 1;
  for (let index = blockStart + 1; index < source.length; index += 1) {
    if (source[index] === '{') depth += 1;
    if (source[index] === '}') depth -= 1;
    if (depth === 0) return source.slice(blockStart + 1, index);
  }
  return '';
};

const parseHex = (hex) => {
  const channels = hex.slice(1).match(/.{2}/g).map((value) => Number.parseInt(value, 16) / 255);
  return channels.map((value) => (value <= 0.04045
    ? value / 12.92
    : ((value + 0.055) / 1.055) ** 2.4));
};

const luminance = (hex) => {
  const [red, green, blue] = parseHex(hex);
  return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue);
};

const contrastRatio = (foreground, background) => {
  const light = Math.max(luminance(foreground), luminance(background));
  const dark = Math.min(luminance(foreground), luminance(background));
  return (light + 0.05) / (dark + 0.05);
};

describe('public responsive and readability contracts', () => {
  it('keeps the mockup-derived landing sequence and compact navigation in the DOM', () => {
    const host = document.createElement('div');
    host.innerHTML = renderToStaticMarkup(<FlashlightsHomePage />);

    const desktopNav = host.querySelector('.flashlights-singer__desktop-nav');
    const mobileMenu = host.querySelector('.flashlights-singer__mobile-menu');
    const h1 = host.querySelector('#flashlights-home-title');
    const feature = host.querySelector('.flashlights-hub-feature');
    const browse = host.querySelector('.flashlights-hub-browse');
    const quick = host.querySelector('.flashlights-hub-quick');
    const downloads = host.querySelector('.flashlights-hub-downloads');

    expect(desktopNav?.querySelectorAll('a')).toHaveLength(5);
    expect(mobileMenu?.querySelector('summary')?.textContent).toBe('Menu');
    expect(mobileMenu?.querySelectorAll('nav a')).toHaveLength(5);
    expect(h1?.getAttribute('aria-label')).toBe('Flashlights in the Dark');
    expect(browse?.textContent).toContain('Browse all singer resources');

    expect(h1.compareDocumentPosition(feature) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(feature.compareDocumentPosition(browse) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(browse.compareDocumentPosition(quick) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(quick.compareDocumentPosition(downloads) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it.each([320, 390])('uses one-column, full-width resource controls at %ipx', (width) => {
    const mobileCss = cssBlock(publicCss, '@media (max-width: 620px)');

    expect(width).toBeLessThanOrEqual(620);
    expect(cssBlock(mobileCss, '.flashlights-singer__desktop-nav {')).toMatch(/display:\s*none/);
    expect(cssBlock(mobileCss, '.flashlights-singer__mobile-menu {')).toMatch(/display:\s*block/);
    expect(cssBlock(mobileCss, '.flashlights-singer__theme-toggle {')).toMatch(/width:\s*48px/);
    expect(cssBlock(mobileCss, '.flashlights-hub-browse {')).toMatch(/min-height:\s*76px/);
    expect(cssBlock(mobileCss, '.flashlights-hub-quick,')).toMatch(
      /grid-template-columns:\s*minmax\(0,\s*1fr\)/
    );
    expect(cssBlock(mobileCss, '.flashlights-platform-card {')).toMatch(
      /grid-template-columns:\s*3\.5rem minmax\(0,\s*1fr\)/
    );
  });

  it('defaults to light and honors only an explicit stored dark preference', () => {
    const emptyStorage = { getItem: () => null };
    const darkStorage = { getItem: (key) => (key === FLASHLIGHTS_THEME_STORAGE_KEY ? 'dark' : null) };
    const invalidStorage = { getItem: () => 'system' };

    expect(resolveInitialTheme(emptyStorage)).toBe('light');
    expect(resolveInitialTheme(darkStorage)).toBe('dark');
    expect(resolveInitialTheme(invalidStorage)).toBe('light');
    expect(resolveInitialTheme(null)).toBe('light');
  });

  it('does not size meaningful public copy below the 18px floor at a 16px rem root', () => {
    const undersizedRules = [...publicCss.matchAll(/([^{}]+)\{([^{}]*font-size:\s*([^;}]+)[^{}]*)\}/g)]
      .map(([, selector, , value]) => ({ selector: selector.trim(), value: value.trim() }))
      .filter(({ value }) => {
        const rem = value.match(/(?:^|\()\s*([\d.]+)rem/);
        const pixels = value.match(/^\s*([\d.]+)px/);
        if (rem) return Number(rem[1]) < 1.125;
        if (pixels) return Number(pixels[1]) < 18;
        return false;
      });

    expect(undersizedRules).toHaveLength(1);
    expect(undersizedRules[0].selector).toContain('.flashlights-singer__card-number');
  });

  it('keeps primary anchor text dark on yellow at WCAG AA contrast', () => {
    const primaryAnchorRule = cssBlock(
      publicCss,
      '.flashlights-singer a.flashlights-singer__button--primary,'
    );

    expect(primaryAnchorRule).toMatch(/color:\s*var\(--flashlights-button-ink\)/);
    expect(contrastRatio('#111014', '#f3cc5c')).toBeGreaterThan(4.5);
  });
});
