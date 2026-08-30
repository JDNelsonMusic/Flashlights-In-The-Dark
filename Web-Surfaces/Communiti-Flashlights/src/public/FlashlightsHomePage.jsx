import React from 'react';
import {
  BookletMockup,
  FlashlightsPageFrame,
  ResourceStatus,
  resourcePath,
} from './FlashlightsPageFrame';
import { flashlightsResourceManifest } from './resourceManifest';

const scoreDownloadLabel = (score) => {
  const megabytes = (score.media.fileSizeBytes / (1024 * 1024)).toFixed(1);
  return `Download score · ${score.media.pageCount} pages · ${megabytes} MB`;
};

export function FlashlightsHomePage({
  basePath = '/flashlights',
  resourceManifest = flashlightsResourceManifest,
}) {
  const score = resourceManifest.resources.score;
  const scoreIsReady = score.status === 'ready';

  return (
    <FlashlightsPageFrame basePath={basePath} currentPage="home">
      <section className="flashlights-singer__hero" aria-labelledby="flashlights-home-title">
        <div className="flashlights-singer__hero-copy">
          <p className="flashlights-singer__eyebrow">Singer rehearsal home</p>
          <h1 id="flashlights-home-title">Flashlights in the Dark</h1>
          <p className="flashlights-singer__lede">
            Find the materials you need to learn your part, warm up, and prepare for rehearsal.
            Begin with the seven quick-practice tracks available today.
          </p>
          <a
            className="flashlights-singer__button flashlights-singer__button--primary"
            href={resourcePath(basePath, 'practice')}
          >
            Start practicing
          </a>
        </div>

        <section className="flashlights-singer__score-feature" aria-labelledby="home-score-title">
          <div>
            <p className="flashlights-singer__eyebrow">Formal score</p>
            <h2 id="home-score-title">Your rehearsal booklet</h2>
            {scoreIsReady ? (
              <p className="flashlights-singer__ready">Score ready</p>
            ) : (
              <ResourceStatus>Score PDF coming soon</ResourceStatus>
            )}
            <p>{scoreIsReady
              ? 'Download the approved 12-page reader-order score, or read the booklet printing notes.'
              : 'The approved reader-order score will appear here as soon as the final 12-page file is ready for public use.'}</p>
            {scoreIsReady ? (
              <a
                className="flashlights-singer__button flashlights-singer__button--primary"
                href={score.url}
                download
              >
                {scoreDownloadLabel(score)}
              </a>
            ) : null}
            <a className="flashlights-singer__text-link" href={resourcePath(basePath, 'score')}>
              Score details and printing notes
            </a>
          </div>
          <BookletMockup />
        </section>
      </section>

      <section className="flashlights-singer__section" aria-labelledby="resources-title">
        <div className="flashlights-singer__section-heading">
          <p className="flashlights-singer__eyebrow">Everything in one place</p>
          <h2 id="resources-title">Singer resources</h2>
        </div>
        <div className="flashlights-singer__card-grid">
          <article className="flashlights-singer__card">
            <p className="flashlights-singer__card-number" aria-hidden="true">01</p>
            <h3>Score</h3>
            {scoreIsReady ? (
              <p className="flashlights-singer__ready">Available now · 12 pages</p>
            ) : (
              <ResourceStatus>Score PDF coming soon</ResourceStatus>
            )}
            <p>See the booklet format and simple duplex printing instructions.</p>
            <a className="flashlights-singer__text-link" href={resourcePath(basePath, 'score')}>
              Read score details
            </a>
          </article>

          <article className="flashlights-singer__card flashlights-singer__card--ready">
            <p className="flashlights-singer__card-number" aria-hidden="true">02</p>
            <h3>Practice tracks</h3>
            <p className="flashlights-singer__ready">Available now · seven choices</p>
            <p>Choose your chorus and voice part. Only one video loads at a time.</p>
            <a className="flashlights-singer__text-link" href={resourcePath(basePath, 'practice')}>
              Choose a practice track
            </a>
          </article>

          <article className="flashlights-singer__card">
            <p className="flashlights-singer__card-number" aria-hidden="true">03</p>
            <h3>Warm up with Clare</h3>
            <ResourceStatus>Videos coming soon</ResourceStatus>
            <p>Clare’s guided warm-ups will be added after captions and transcripts are approved.</p>
            <a className="flashlights-singer__text-link" href={`${resourcePath(basePath, 'videos')}#warm-ups`}>
              Read warm-up availability
            </a>
          </article>

          <article className="flashlights-singer__card">
            <p className="flashlights-singer__card-number" aria-hidden="true">04</p>
            <h3>Watch the presentation</h3>
            <ResourceStatus>Presentation coming soon</ResourceStatus>
            <p>The unlisted demonstration will appear after public-exposure and caption review.</p>
            <a
              className="flashlights-singer__text-link"
              href={`${resourcePath(basePath, 'videos')}#presentation`}
            >
              Read presentation availability
            </a>
          </article>

          <article className="flashlights-singer__card flashlights-singer__card--ready">
            <p className="flashlights-singer__card-number" aria-hidden="true">05</p>
            <h3>Advanced mixer</h3>
            <p className="flashlights-singer__ready">Available now · 13 parts</p>
            <p>Open the full rehearsal mixer when you need detailed control over individual parts.</p>
            <a className="flashlights-singer__text-link" href={resourcePath(basePath, 'mixer')}>
              Open the advanced mixer
            </a>
          </article>
        </div>
      </section>
    </FlashlightsPageFrame>
  );
}

export default FlashlightsHomePage;
