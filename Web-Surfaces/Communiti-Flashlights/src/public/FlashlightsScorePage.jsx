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
  return `Download score PDF · ${score.media.pageCount} pages · ${megabytes} MB`;
};

export function FlashlightsScorePage({
  basePath = '/flashlights',
  resourceManifest = flashlightsResourceManifest,
}) {
  const score = resourceManifest.resources.score;
  const scoreIsReady = score.status === 'ready';

  return (
    <FlashlightsPageFrame basePath={basePath} currentPage="score">
      <header className="flashlights-singer__page-heading">
        <p className="flashlights-singer__eyebrow">Formal score</p>
        <h1>Score booklet</h1>
        <p className="flashlights-singer__lede">
          This page is the permanent home for the singer score and booklet-printing help.
        </p>
      </header>

      <section className="flashlights-singer__paper-panel flashlights-singer__score-page" aria-labelledby="score-status-title">
        <BookletMockup />
        <div>
          <h2 id="score-status-title">Score availability</h2>
          {scoreIsReady ? (
            <p className="flashlights-singer__ready">Score ready</p>
          ) : (
            <ResourceStatus>Score PDF coming soon</ResourceStatus>
          )}
          <p>{scoreIsReady
            ? 'The approved public score is a 12-page, 8.5×11 reader-order PDF.'
            : 'There is no approved public score download yet. When the final file is supplied, this page will show a normal download link labeled with its 12-page count and file size.'}</p>
          {scoreIsReady ? (
            <a
              className="flashlights-singer__button flashlights-singer__button--primary"
              href={score.url}
              download
            >
              {scoreDownloadLabel(score)}
            </a>
          ) : null}
          <p>You will never need an account to download the score from this public page.</p>
        </div>
      </section>

      <section className="flashlights-singer__section flashlights-singer__reading" aria-labelledby="printing-title">
        <h2 id="printing-title">How booklet printing will work</h2>
        <p>The download will be a standard 8.5×11 PDF in reader order. To make a folded booklet:</p>
        <ol>
          <li>Choose booklet printing in your PDF reader.</li>
          <li>Select 11×17 paper and print on both sides.</li>
          <li>Flip on the short edge if your printer asks.</li>
          <li>Fold the three printed sheets in half to make the 12-page booklet.</li>
        </ol>
        <p>
          Prefer regular pages? Print the same file on 8.5×11 paper at actual size.
        </p>
        <a className="flashlights-singer__text-link" href={resourcePath(basePath, 'practice')}>
          Practice while the score is being prepared
        </a>
      </section>
    </FlashlightsPageFrame>
  );
}

export default FlashlightsScorePage;
