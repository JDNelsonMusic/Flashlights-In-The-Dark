import React from 'react';
import { FlashlightsPageFrame, ResourceStatus, resourcePath } from './FlashlightsPageFrame';

export function FlashlightsDocumentationPage({ basePath = '/flashlights' }) {
  return (
    <FlashlightsPageFrame basePath={basePath}>
      <header className="flashlights-singer__page-heading">
        <p className="flashlights-singer__eyebrow">Singer guide</p>
        <h1>How to use these resources</h1>
        <p className="flashlights-singer__lede">
          Start with one practice track, add the score when it is published, and open the advanced
          mixer only when you want detailed control over all 13 parts.
        </p>
      </header>

      <section className="flashlights-singer__section" aria-labelledby="documentation-resources-title">
        <div className="flashlights-singer__section-heading">
          <h2 id="documentation-resources-title">Choose what you need</h2>
        </div>
        <div className="flashlights-singer__documentation-grid">
          <article className="flashlights-singer__card">
            <h3>Formal score</h3>
            <ResourceStatus>Score PDF coming soon</ResourceStatus>
            <p>Check the score page for availability and booklet-printing instructions.</p>
            <a className="flashlights-singer__text-link" href={resourcePath(basePath, 'score')}>
              Go to the score page
            </a>
          </article>
          <article className="flashlights-singer__card flashlights-singer__card--ready">
            <h3>Quick practice</h3>
            <p className="flashlights-singer__ready">Available now · seven tracks</p>
            <p>Choose the Shadow Chorus, Light Chorus, or full-ensemble recording you need.</p>
            <a className="flashlights-singer__text-link" href={resourcePath(basePath, 'practice')}>
              Choose a practice track
            </a>
          </article>
          <article className="flashlights-singer__card">
            <h3>Warm-ups and presentation</h3>
            <ResourceStatus>Videos coming soon</ResourceStatus>
            <p>See the approval and accessibility status for Clare’s warm-ups and the presentation.</p>
            <a className="flashlights-singer__text-link" href={resourcePath(basePath, 'videos')}>
              Check video availability
            </a>
          </article>
          <article className="flashlights-singer__card flashlights-singer__card--ready">
            <h3>Advanced mixer</h3>
            <p className="flashlights-singer__ready">Available now · 13 parts</p>
            <p>Play synchronized stems, adjust levels, and use mute or solo for sectional work.</p>
            <a className="flashlights-singer__text-link" href={resourcePath(basePath, 'mixer')}>
              Open the 13-part mixer
            </a>
          </article>
        </div>
      </section>

      <section className="flashlights-singer__section flashlights-singer__reading" aria-labelledby="practice-routine-title">
        <h2 id="practice-routine-title">A simple practice routine</h2>
        <ol>
          <li>Warm up gently before singing at full volume.</li>
          <li>Listen once while following your text or score.</li>
          <li>Sing with your own part, then try the full-ensemble track.</li>
          <li>Use the mixer to lower your part and check whether you can hold it independently.</li>
        </ol>
        <p>Playback never starts automatically. You can also open every practice track directly on YouTube.</p>
      </section>
    </FlashlightsPageFrame>
  );
}

export default FlashlightsDocumentationPage;
