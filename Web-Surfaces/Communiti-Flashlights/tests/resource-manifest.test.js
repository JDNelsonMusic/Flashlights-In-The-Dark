import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  PRACTICE_TRACKS,
  flashlightsResourceManifest,
  validateFlashlightsResourceManifest,
} from '../src/resources';

const cloneManifest = () => structuredClone(flashlightsResourceManifest);

const makeScoreReady = (manifest) => {
  const score = manifest.resources.score;
  score.status = 'ready';
  score.url = '/flashlights/assets/flashlights-in-the-dark-score.pdf';
  score.publicExposureApprovalRef = 'FITD-SCORE-PUBLIC-APPROVAL';
  score.media.pageCount = 12;
  score.media.fileSizeBytes = 1_234_567;
  return score;
};

const makeReadyVideo = ({ id, label, youtubeId }) => ({
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
    transcript: {
      status: 'verified',
      url: `/flashlights/transcripts/${id}`,
    },
  },
});

const makeWarmUpsReady = (manifest) => {
  const warmUps = manifest.resources.warmUps;
  warmUps.status = 'ready';
  warmUps.url = '/flashlights/videos#warm-ups';
  warmUps.publicExposureApprovalRef = 'FITD-WARMUPS-PUBLIC-APPROVAL';
  warmUps.captionStatus = 'verified';
  warmUps.media.items = [
    makeReadyVideo({ id: 'clare-breath', label: 'Breath and release', youtubeId: 'warmup00001' }),
    makeReadyVideo({ id: 'clare-range', label: 'Gentle range', youtubeId: 'warmup00002' }),
  ];
  warmUps.media.itemCount = warmUps.media.items.length;
  return warmUps;
};

describe('Flashlights resource manifest', () => {
  it('validates the release manifest', () => {
    expect(validateFlashlightsResourceManifest(flashlightsResourceManifest)).toBe(
      flashlightsResourceManifest
    );
  });

  it('contains exactly the seven approved practice mappings', () => {
    expect(PRACTICE_TRACKS.map(({ label, url }) => ({ label, url }))).toEqual([
      { label: 'Shadow Chorus — Sopranos', url: 'https://youtu.be/DD_Q9AGe3Vg' },
      { label: 'Shadow Chorus — Altos', url: 'https://youtu.be/8Sq4xGM-6xc' },
      { label: 'Shadow Chorus — Baritones', url: 'https://youtu.be/Bwhv9A7p63M' },
      { label: 'Light Chorus — Sopranos 1–2', url: 'https://youtu.be/Xpy339h5v4U' },
      { label: 'Light Chorus — Altos 1–2', url: 'https://youtu.be/PjMFdOPk3Zw' },
      { label: 'Light Chorus — Tenor/Bass', url: 'https://youtu.be/STO9SbsjrlY' },
      { label: 'All voices without electronics', url: 'https://youtu.be/xEPj1p83vHY' },
    ]);
  });

  it('accepts a fully described 12-page Letter reader-order booklet', () => {
    const manifest = cloneManifest();
    makeScoreReady(manifest);
    expect(() => validateFlashlightsResourceManifest(manifest)).not.toThrow();
  });

  it.each([
    ['page count', (score) => { score.media.pageCount = 11; }, /exactly 12 pages/],
    ['page size', (score) => { score.media.pageSize.widthInches = 8; }, /US Letter/],
    ['file size', (score) => { score.media.fileSizeBytes = 0; }, /positive file size/],
    ['reader order', (score) => { score.media.readerOrder = false; }, /reader order/],
    ['sheet size', (score) => { score.media.bookletPrint.sheetSize = '8.5×11'; }, /three 11×17 sheets/],
    ['sheet count', (score) => { score.media.bookletPrint.sheetCount = 4; }, /three 11×17 sheets/],
    ['duplex printing', (score) => { score.media.bookletPrint.duplex = false; }, /duplex booklet/],
    ['PDF URL', (score) => { score.url = '/flashlights/score.txt'; }, /point to a PDF/],
    ['public approval', (score) => { score.publicExposureApprovalRef = null; }, /public-exposure approval/],
  ])('rejects a ready score with invalid %s metadata', (_name, mutate, expectedError) => {
    const manifest = cloneManifest();
    const score = makeScoreReady(manifest);
    mutate(score);
    expect(() => validateFlashlightsResourceManifest(manifest)).toThrow(expectedError);
  });

  it.each(['warmUps', 'presentation'])('fails closed when %s is merely marked ready with a URL', (key) => {
    const manifest = cloneManifest();
    manifest.resources[key].status = 'ready';
    manifest.resources[key].url = 'https://youtu.be/futureVideo';
    expect(() => validateFlashlightsResourceManifest(manifest)).toThrow(/public-exposure approval|verified captions/);
  });

  it('requires verified captions and an available transcript for a ready presentation', () => {
    const manifest = cloneManifest();
    const video = makeReadyVideo({
      ...manifest.resources.presentation,
      youtubeId: 'present0001',
    });
    manifest.resources.presentation = video;
    video.media.transcriptRequired = false;
    expect(() => validateFlashlightsResourceManifest(manifest)).toThrow(/require a transcript/);

    video.media.transcriptRequired = true;
    video.media.transcript.url = null;
    expect(() => validateFlashlightsResourceManifest(manifest)).toThrow(/available, verified transcript/);

    video.media.transcript.url = '/flashlights/transcripts/presentation';
    expect(() => validateFlashlightsResourceManifest(manifest)).not.toThrow();
  });

  it('validates every exposed item in a ready warm-up collection', () => {
    const manifest = cloneManifest();
    const warmUps = makeWarmUpsReady(manifest);
    expect(() => validateFlashlightsResourceManifest(manifest)).not.toThrow();

    warmUps.media.items[1].media.privacyEnhancedEmbedHost = 'www.youtube.com';
    expect(() => validateFlashlightsResourceManifest(manifest)).toThrow(/privacy-enhanced/);
  });

  it.each([
    ['status', (item) => { item.status = 'coming-soon'; }, /explicitly marked ready/],
    ['label', (item) => { item.label = ''; }, /id and label/],
    ['direct URL', (item) => { item.url = 'https://youtu.be/wrong000001'; }, /matching its video ID/],
    ['YouTube ID', (item) => { item.media.youtubeId = 'short'; }, /valid YouTube video ID/],
    ['captions', (item) => { item.captionStatus = 'required-before-release'; }, /verified captions/],
    ['transcript', (item) => { item.media.transcript.url = null; }, /available, verified transcript/],
    ['public approval', (item) => { item.publicExposureApprovalRef = null; }, /public-exposure approval/],
    ['embed host', (item) => { item.media.privacyEnhancedEmbedHost = 'www.youtube.com'; }, /privacy-enhanced/],
    ['autoplay', (item) => { item.media.autoplay = true; }, /non-autoplay/],
  ])('rejects a ready warm-up item with invalid %s metadata', (_name, mutate, expectedError) => {
    const manifest = cloneManifest();
    const warmUps = makeWarmUpsReady(manifest);
    mutate(warmUps.media.items[1]);
    expect(() => validateFlashlightsResourceManifest(manifest)).toThrow(expectedError);
  });

  it('rejects empty, mismatched, or duplicate ready warm-up collections', () => {
    const manifest = cloneManifest();
    const warmUps = makeWarmUpsReady(manifest);
    warmUps.media.itemCount = 1;
    expect(() => validateFlashlightsResourceManifest(manifest)).toThrow(/itemCount/);

    warmUps.media.itemCount = 2;
    warmUps.media.items[1].id = warmUps.media.items[0].id;
    expect(() => validateFlashlightsResourceManifest(manifest)).toThrow(/duplicate warm-up video id/);

    warmUps.media.items = [];
    warmUps.media.itemCount = 0;
    expect(() => validateFlashlightsResourceManifest(manifest)).toThrow(/at least one approved video item/);
  });

  it('publishes every source entrypoint through package exports', () => {
    const packageJson = JSON.parse(
      readFileSync(resolve(process.cwd(), 'package.json'), 'utf8')
    );
    expect(packageJson.exports).toMatchObject({
      '.': './dist/index.js',
      './landing': './dist/landing.js',
      './score': './dist/score.js',
      './practice': './dist/practice.js',
      './videos': './dist/videos.js',
      './mixer': './dist/mixer.js',
      './documentation': './dist/documentation.js',
      './install': './dist/install.js',
      './privacy': './dist/privacy.js',
      './resources': './dist/resources.js',
    });
  });
});
