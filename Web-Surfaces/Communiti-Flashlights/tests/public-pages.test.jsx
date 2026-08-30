import React, { act } from 'react';
import { createRoot } from 'react-dom/client';
import { renderToStaticMarkup } from 'react-dom/server';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import FlashlightsHomePage from '../src/landing';
import FlashlightsPracticePage from '../src/practice';
import FlashlightsScorePage from '../src/score';
import FlashlightsVideosPage from '../src/videos';
import { flashlightsResourceManifest } from '../src/resources';

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

describe('public singer pages', () => {
  it('renders the approved home actions and an honest score placeholder', () => {
    const markup = renderToStaticMarkup(<FlashlightsHomePage />);
    expect(markup).toContain('<h1 id="flashlights-home-title">Flashlights in the Dark</h1>');
    expect(markup).toContain('Start practicing');
    expect(markup).toContain('Score PDF coming soon');
    expect(markup).toContain('12-page booklet · three 11×17 sheets · folds to 8.5×11');
    expect(markup).not.toMatch(/href="[^"]+\.pdf/i);
    expect(markup).not.toContain('<iframe');
  });

  it('renders score status and printing guidance without a fake download', () => {
    const markup = renderToStaticMarkup(<FlashlightsScorePage />);
    expect(markup).toContain('Score PDF coming soon');
    expect(markup).toContain('11×17 paper');
    expect(markup).not.toMatch(/<a[^>]+download/i);
    expect(markup).not.toMatch(/<button[^>]*disabled/i);
  });

  it('renders a real page-count and file-size download when a validated score is ready', () => {
    const manifest = structuredClone(flashlightsResourceManifest);
    const score = manifest.resources.score;
    score.status = 'ready';
    score.url = '/flashlights/flashlights-score.pdf';
    score.publicExposureApprovalRef = 'FITD-SCORE-PUBLIC-APPROVAL';
    score.media.pageCount = 12;
    score.media.fileSizeBytes = 2 * 1024 * 1024;
    const markup = renderToStaticMarkup(<FlashlightsScorePage resourceManifest={manifest} />);
    expect(markup).toContain('Download score PDF · 12 pages · 2.0 MB');
    expect(markup).toContain('href="/flashlights/flashlights-score.pdf"');
    expect(markup).toContain('download=""');
    expect(markup).not.toContain('Score PDF coming soon');
  });

  it('renders video placeholders without players or fake controls', () => {
    const markup = renderToStaticMarkup(<FlashlightsVideosPage />);
    expect(markup).toContain('Warm-up videos coming soon');
    expect(markup).toContain('Presentation video coming soon');
    expect(markup).toContain('caption review');
    expect(markup).not.toContain('<iframe');
    expect(markup).not.toContain('<button');
  });
});

describe('practice player behavior', () => {
  let container;
  let root;

  beforeEach(async () => {
    container = document.createElement('div');
    document.body.append(container);
    root = createRoot(container);
    await act(async () => {
      root.render(<FlashlightsPracticePage />);
    });
  });

  afterEach(async () => {
    await act(async () => root.unmount());
    container.remove();
  });

  it('offers exactly seven choices without loading a player initially', () => {
    const playButtons = [...container.querySelectorAll('button')].filter((button) =>
      button.textContent.startsWith('Play ')
    );
    expect(playButtons).toHaveLength(7);
    expect(container.querySelectorAll('iframe')).toHaveLength(0);
    expect(container.querySelectorAll('a[href^="https://youtu.be/"]')).toHaveLength(7);
  });

  it('loads one privacy-enhanced, non-autoplay player at a time', async () => {
    const playButtons = [...container.querySelectorAll('button')].filter((button) =>
      button.textContent.startsWith('Play ')
    );

    await act(async () => playButtons[0].click());
    let frames = container.querySelectorAll('iframe');
    expect(frames).toHaveLength(1);
    expect(frames[0].src).toBe('https://www.youtube-nocookie.com/embed/DD_Q9AGe3Vg?rel=0');
    expect(frames[0].src).not.toContain('autoplay=1');

    const nextButton = [...container.querySelectorAll('button')].find((button) =>
      button.textContent.includes('Play Altos practice track')
    );
    await act(async () => nextButton.click());
    frames = container.querySelectorAll('iframe');
    expect(frames).toHaveLength(1);
    expect(frames[0].src).toBe('https://www.youtube-nocookie.com/embed/8Sq4xGM-6xc?rel=0');
  });
});
