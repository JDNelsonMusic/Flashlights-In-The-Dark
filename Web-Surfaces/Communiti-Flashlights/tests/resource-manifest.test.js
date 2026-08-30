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

  it.each(['warmUps', 'presentation'])('requires verified captions and a transcript for ready %s', (key) => {
    const manifest = cloneManifest();
    const video = manifest.resources[key];
    video.status = 'ready';
    video.url = 'https://youtu.be/approvedVideo';
    video.publicExposureApprovalRef = 'FITD-VIDEO-PUBLIC-APPROVAL';
    video.captionStatus = 'verified';
    video.media.transcriptRequired = false;
    expect(() => validateFlashlightsResourceManifest(manifest)).toThrow(/require a transcript/);

    video.media.transcriptRequired = true;
    expect(() => validateFlashlightsResourceManifest(manifest)).not.toThrow();
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
      './privacy': './dist/privacy.js',
      './resources': './dist/resources.js',
    });
  });
});
