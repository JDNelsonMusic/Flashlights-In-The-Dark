import React from 'react';
import FlashlightsMultiTrackMixer from '../components/FlashlightsMultiTrackMixer';
import { FlashlightsPageFrame } from './FlashlightsPageFrame';

export function FlashlightsMixer({ basePath = '/flashlights' }) {
  return (
    <FlashlightsPageFrame basePath={basePath} currentPage="mixer">
      <header className="flashlights-singer__page-heading">
        <p className="flashlights-singer__eyebrow">Advanced rehearsal tool</p>
        <h1>13-part mixer</h1>
        <p className="flashlights-singer__lede">
          Play all rehearsal stems in sync. Drag across a waveform to choose a loop, jump by rehearsal
          measure, and use Solo or Mute to shape the balance you need.
        </p>
      </header>
      <section aria-labelledby="advanced-mixer-controls-title">
        <h2 id="advanced-mixer-controls-title" className="flashlights-singer__section-title">
          Mixing controls
        </h2>
        <FlashlightsMultiTrackMixer />
      </section>
    </FlashlightsPageFrame>
  );
}

export default FlashlightsMixer;
