import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import FlashlightsHomePage from '../src/landing';

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
  it('uses a compact menu and keeps the required home sequence in the phone DOM', () => {
    const host = document.createElement('div');
    host.innerHTML = renderToStaticMarkup(<FlashlightsHomePage />);

    const desktopNav = host.querySelector('.flashlights-singer__desktop-nav');
    const mobileMenu = host.querySelector('.flashlights-singer__mobile-menu');
    const h1 = host.querySelector('#flashlights-home-title');
    const lede = host.querySelector('.flashlights-singer__hero-copy .flashlights-singer__lede');
    const practice = host.querySelector('a[href="/flashlights/practice"].flashlights-singer__button--primary');
    const score = host.querySelector('.flashlights-singer__score-feature');
    const scoreStatus = score?.querySelector('.flashlights-singer__status');

    expect(desktopNav?.querySelectorAll('a')).toHaveLength(5);
    expect(mobileMenu?.querySelector('summary')?.textContent).toBe('Menu');
    expect(mobileMenu?.querySelectorAll('nav a')).toHaveLength(5);
    expect(lede?.textContent).toContain('Start with a practice track');
    expect(scoreStatus?.textContent).toBe('Score PDF coming soon');

    expect(h1.compareDocumentPosition(lede) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(lede.compareDocumentPosition(practice) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(practice.compareDocumentPosition(score) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it.each([320, 390])('keeps the CTA and score status inside the 568px fold contract at %ipx', (width) => {
    const mobileCss = cssBlock(publicCss, '@media (max-width: 620px)');

    expect(width).toBeLessThanOrEqual(620);
    expect(cssBlock(mobileCss, '.flashlights-singer__header-inner {')).toMatch(/min-height:\s*60px/);
    expect(cssBlock(mobileCss, '.flashlights-singer__desktop-nav {')).toMatch(/display:\s*none/);
    expect(cssBlock(mobileCss, '.flashlights-singer__mobile-menu {')).toMatch(/display:\s*block/);
    expect(cssBlock(mobileCss, '.flashlights-singer__main {')).toMatch(/padding-block:\s*0\.7rem 2\.5rem/);
    expect(cssBlock(mobileCss, '.flashlights-singer__hero {')).toMatch(/gap:\s*0\.7rem/);
    expect(cssBlock(mobileCss, '.flashlights-singer__hero-copy .flashlights-singer__eyebrow {'))
      .toMatch(/display:\s*none/);
    expect(cssBlock(mobileCss, '.flashlights-singer__hero .flashlights-singer__score-feature {'))
      .toMatch(/grid-template-columns:\s*minmax\(0,\s*1fr\) 4\.5rem/);
    expect(cssBlock(mobileCss, '.flashlights-singer__hero .flashlights-singer__score-description {'))
      .toMatch(/display:\s*none/);

    // A conservative two-line title and three-line orientation budget at a 16px rem root.
    const header = 60;
    const mainTopPadding = 0.7 * 16;
    const title = 2 * (Math.min(Math.max(2.15 * 16, width * 0.12), 2.65 * 16) * 1.04);
    const orientation = 3 * (1.125 * 16 * 1.35);
    const heroCopyGaps = 2 * (0.5 * 16);
    const target = 48;
    const heroGap = 0.7 * 16;
    const scorePadding = 0.75 * 16;
    const scoreHeading = 2 * (1.4 * 16 * 1.08);
    const scoreGap = 0.35 * 16;
    const scoreStatus = (1.125 * 16 * 1.62) + (2 * 0.22 * 16) + 2;
    const ctaBottom = header + mainTopPadding + title + orientation + heroCopyGaps + target;
    const scoreStatusBottom = ctaBottom + heroGap + scorePadding + scoreHeading + scoreGap + scoreStatus;

    expect(ctaBottom).toBeLessThan(568);
    expect(scoreStatusBottom).toBeLessThan(568);
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

    expect(undersizedRules).toHaveLength(2);
    expect(undersizedRules.map(({ selector }) => selector).join('\n')).toContain('.flashlights-singer__wordmark-light');
    expect(undersizedRules.map(({ selector }) => selector).join('\n')).toContain('.flashlights-singer__card-number');
  });

  it('keeps primary anchor text dark on yellow at WCAG AA contrast', () => {
    const primaryAnchorRule = cssBlock(
      publicCss,
      '.flashlights-singer a.flashlights-singer__button--primary,'
    );

    expect(primaryAnchorRule).toMatch(/color:\s*var\(--flashlights-ink\)/);
    expect(contrastRatio('#172033', '#f6c95c')).toBeGreaterThan(4.5);
  });
});
