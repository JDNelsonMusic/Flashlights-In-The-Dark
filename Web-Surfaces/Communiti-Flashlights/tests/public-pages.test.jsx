import React, { act } from 'react';
import { createRoot } from 'react-dom/client';
import { renderToStaticMarkup } from 'react-dom/server';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import FlashlightsHomePage from '../src/landing';
import FlashlightsPracticePage from '../src/practice';
import FlashlightsScorePage from '../src/score';
import FlashlightsVideosPage from '../src/videos';
import FlashlightsMixer from '../src/mixer';
import FlashlightsDocumentationPage from '../src/documentation';
import FlashlightsInstallPage, { GOOGLE_PLAY_URL, TESTFLIGHT_URL } from '../src/install';
import FlashlightsPrivacyPage from '../src/privacy';
import { flashlightsResourceManifest } from '../src/resources';

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

const readyVideo = ({ id, label, youtubeId }) => ({
  id,
  status: 'ready',
  label,
  url: `https://youtu.be/${youtubeId}`,
  updated: '2026-08-29',
  rightsReviewRef: 'FITD-VIDEO-RIGHTS-APPROVAL',
  publicExposureApprovalRef: 'FITD-VIDEO-PUBLIC-APPROVAL',
  captionStatus: 'verified',
  media: {
    kind: 'youtube-video',
    provider: 'YouTube',
    privacyEnhancedEmbedHost: 'www.youtube-nocookie.com',
    autoplay: false,
    youtubeId,
    transcriptRequired: true,
    transcript: { status: 'verified', url: `/flashlights/transcripts/${id}` },
  },
});

const readyVideoManifest = () => {
  const manifest = structuredClone(flashlightsResourceManifest);
  const warmUps = manifest.resources.warmUps;
  warmUps.status = 'ready';
  warmUps.url = '/flashlights/videos#warm-ups';
  warmUps.publicExposureApprovalRef = 'FITD-WARMUPS-PUBLIC-APPROVAL';
  warmUps.captionStatus = 'verified';
  warmUps.media.items = [
    readyVideo({ id: 'clare-breath', label: 'Breath and release', youtubeId: 'warmup00001' }),
    readyVideo({ id: 'clare-range', label: 'Gentle range', youtubeId: 'warmup00002' }),
  ];
  warmUps.media.itemCount = 2;
  manifest.resources.presentation = readyVideo({
    id: 'presentation-demo',
    label: 'Flashlights presentation',
    youtubeId: 'present0001',
  });
  return manifest;
};

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

  it('keeps documentation owner-safe and points to the approved resource routes', () => {
    const markup = renderToStaticMarkup(<FlashlightsDocumentationPage />);
    expect(markup).toContain('How to use these resources');
    expect(markup).toContain('href="/flashlights/score"');
    expect(markup).toContain('href="/flashlights/practice"');
    expect(markup).toContain('href="/flashlights/videos"');
    expect(markup).toContain('href="/flashlights/mixer"');
    expect(markup).not.toMatch(/href="[^"]+\.pdf/i);
    expect(markup).not.toContain('Mockup audio');
  });

  it('preserves the iOS and Android install links without the legacy hub', () => {
    const markup = renderToStaticMarkup(<FlashlightsInstallPage />);
    expect(markup.match(/<h1/g)).toHaveLength(1);
    expect(markup).toContain(`href="${TESTFLIGHT_URL}"`);
    expect(markup).toContain(`href="${GOOGLE_PLAY_URL}"`);
    expect(markup).not.toContain('FlashlightsInTheDarkTool');
  });

  it('renders a framed privacy page with one h1 and logical h2 sections', () => {
    const markup = renderToStaticMarkup(<FlashlightsPrivacyPage />);
    expect(markup.match(/<h1/g)).toHaveLength(1);
    expect(markup.match(/<h2/g).length).toBeGreaterThanOrEqual(6);
    expect(markup).toContain('flashlights-singer__header');
    expect(markup).toContain('Skip to main content');
  });

  it('retains the existing waveform, loop, measure-marker, mute, and solo mixer workflow', () => {
    const markup = renderToStaticMarkup(<FlashlightsMixer />);
    expect(markup.match(/class="flashlights-track-row/g)).toHaveLength(13);
    expect(markup.match(/flashlights-track-waveform"/g)).toHaveLength(13);
    expect(markup).toContain('Loop Selection');
    expect(markup).toContain('Set loop start here');
    expect(markup).toContain('aria-label="Jump to rehearsal measure 2"');
    expect(markup).toContain('Click anywhere in a waveform');
    expect(markup).toContain('flashlights-rehearsal-marker');
    expect(markup).toContain('aria-label="Solo Sopranos — Parts 1 &amp; 2"');
    expect(markup).toContain('aria-label="Mute Sopranos — Parts 1 &amp; 2"');
    expect(markup).not.toMatch(/href="[^"]+\.pdf/i);
  });
});

describe('approved video player behavior', () => {
  let container;
  let root;

  beforeEach(async () => {
    container = document.createElement('div');
    document.body.append(container);
    root = createRoot(container);
    await act(async () => {
      root.render(<FlashlightsVideosPage resourceManifest={readyVideoManifest()} />);
    });
  });

  afterEach(async () => {
    await act(async () => root.unmount());
    container.remove();
  });

  it('renders every approved choice without loading an iframe initially', () => {
    expect(container.querySelectorAll('button[aria-expanded]')).toHaveLength(3);
    expect(container.querySelectorAll('a[href^="https://youtu.be/"]')).toHaveLength(3);
    expect(container.querySelectorAll('iframe')).toHaveLength(0);
  });

  it('shares one privacy-enhanced, non-autoplay player across warm-ups and presentation', async () => {
    const buttons = [...container.querySelectorAll('button[aria-expanded]')];
    await act(async () => buttons[0].click());
    let frames = container.querySelectorAll('iframe');
    expect(frames).toHaveLength(1);
    expect(frames[0].src).toBe('https://www.youtube-nocookie.com/embed/warmup00001?rel=0');
    expect(frames[0].src).not.toContain('autoplay=1');

    const presentationButton = [...container.querySelectorAll('button[aria-expanded]')].find((button) =>
      button.textContent.includes('Flashlights presentation')
    );
    await act(async () => presentationButton.click());
    frames = container.querySelectorAll('iframe');
    expect(frames).toHaveLength(1);
    expect(frames[0].src).toBe('https://www.youtube-nocookie.com/embed/present0001?rel=0');
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
