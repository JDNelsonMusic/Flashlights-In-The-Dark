import React from 'react';
import { FlashlightsPageFrame, ResourceStatus } from './FlashlightsPageFrame';

export function FlashlightsVideosPage({ basePath = '/flashlights' }) {
  return (
    <FlashlightsPageFrame basePath={basePath} currentPage="videos">
      <header className="flashlights-singer__page-heading">
        <p className="flashlights-singer__eyebrow">Guided video resources</p>
        <h1>Warm-ups and presentation</h1>
        <p className="flashlights-singer__lede">
          This is the permanent home for Clare’s warm-ups and the Flashlights presentation.
        </p>
      </header>

      <div className="flashlights-singer__video-placeholders">
        <section id="warm-ups" className="flashlights-singer__paper-panel" aria-labelledby="warm-ups-title">
          <div className="flashlights-singer__placeholder-mark" aria-hidden="true">C</div>
          <div>
            <p className="flashlights-singer__eyebrow">Prepare your voice</p>
            <h2 id="warm-ups-title">Warm up with Clare</h2>
            <ResourceStatus>Warm-up videos coming soon</ResourceStatus>
            <p>
              No videos are public yet. They will be activated only after explicit public-exposure
              approval, caption review, and complete transcripts.
            </p>
          </div>
        </section>

        <section id="presentation" className="flashlights-singer__paper-panel" aria-labelledby="presentation-title">
          <div className="flashlights-singer__placeholder-mark" aria-hidden="true">▶</div>
          <div>
            <p className="flashlights-singer__eyebrow">See the whole piece</p>
            <h2 id="presentation-title">Watch the presentation</h2>
            <ResourceStatus>Presentation video coming soon</ResourceStatus>
            <p>
              The unlisted demonstration is not approved for this public page yet. When it is ready,
              it will use a click-to-load, non-autoplay player with captions and a transcript.
            </p>
          </div>
        </section>
      </div>
    </FlashlightsPageFrame>
  );
}

export default FlashlightsVideosPage;
