import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import FlashlightsMixer from '../src/mixer';
import { FLASHLIGHTS_REHEARSAL_MARKERS } from '../src/components/FlashlightsMultiTrackMixer';

const mixerCss = readFileSync(
  resolve(process.cwd(), 'src/components/FlashlightsMultiTrackMixer.css'),
  'utf8'
);

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

describe('mobile rehearsal markers', () => {
  it('renders every rehearsal landmark as a labeled button', () => {
    const host = document.createElement('div');
    host.innerHTML = renderToStaticMarkup(<FlashlightsMixer />);
    const markerRow = host.querySelector('.flashlights-rehearsal-marker-row');
    const markers = markerRow?.querySelectorAll('button.flashlights-rehearsal-marker') ?? [];

    expect(markerRow).not.toBeNull();
    expect(markers).toHaveLength(FLASHLIGHTS_REHEARSAL_MARKERS.length);
    markers.forEach((marker) => {
      expect(marker.getAttribute('aria-label')).toMatch(/^Jump to rehearsal measure \d+$/);
      expect(marker.querySelector('.flashlights-rehearsal-label')?.textContent).toMatch(/^m\. \d+$/);
    });
  });

  it.each([320, 390])(
    'uses a non-positioned, wrapping 48px target layout at %ipx',
    (viewportWidth) => {
      const mobilePrelude = '@media (max-width: 640px)';
      const mobileCss = cssBlock(mixerCss, mobilePrelude);
      const markerRowCss = cssBlock(mobileCss, '.flashlights-rehearsal-marker-row {');
      const markerCss = cssBlock(mobileCss, '.flashlights-rehearsal-marker {');
      const tickCss = cssBlock(mobileCss, '.flashlights-rehearsal-tick {');
      const measureGridCss = cssBlock(mobileCss, '.flashlights-measure-grid {');
      const measureLabelCss = cssBlock(mobileCss, '.flashlights-measure-label {');

      expect(viewportWidth).toBeLessThanOrEqual(640);
      expect(markerRowCss).toMatch(/display:\s*grid/);
      expect(markerRowCss).toMatch(
        /grid-template-columns:\s*repeat\(auto-fit,\s*minmax\(4\.75rem,\s*1fr\)\)/
      );
      expect(markerRowCss).toMatch(/height:\s*auto/);
      expect(markerCss).toMatch(/position:\s*static/);
      expect(markerCss).toMatch(/transform:\s*none/);
      expect(markerCss).toMatch(/width:\s*100%/);
      expect(markerCss).toMatch(/min-width:\s*48px/);
      expect(markerCss).toMatch(/min-height:\s*48px/);
      expect(tickCss).toMatch(/display:\s*none/);
      expect(measureGridCss).toMatch(/height:\s*1\.5rem/);
      expect(measureLabelCss).toMatch(/display:\s*none/);
    }
  );

  it('retains percentage-positioned markers outside the mobile override', () => {
    const desktopMarkerCss = cssBlock(mixerCss, '.flashlights-rehearsal-marker {');

    expect(desktopMarkerCss).toMatch(/position:\s*absolute/);
    expect(desktopMarkerCss).toMatch(/transform:\s*translateX\(-50%\)/);
  });
});
