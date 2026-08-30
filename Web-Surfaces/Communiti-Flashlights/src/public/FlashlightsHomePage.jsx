import React from 'react';
import { FlashlightsPageFrame, resourcePath } from './FlashlightsPageFrame';

export const IOS_DOWNLOAD_URL = 'https://keex.ai/flashlights/ios';
export const ANDROID_DOWNLOAD_URL = 'https://keex.ai/flashlights/android';

function AppleMark() {
  return (
    <svg className="flashlights-platform-mark" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701" />
    </svg>
  );
}

function AndroidMark() {
  return (
    <svg className="flashlights-platform-mark" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path d="M18.44 5.56 16.41 9.06a12.2 12.2 0 0 0-8.79-.01L5.6 5.56a1.1 1.1 0 0 0-1.52-.39 1.1 1.1 0 0 0-.39 1.5l1.95 3.36A12.1 12.1 0 0 0 0 18.99h24a12.13 12.13 0 0 0-5.62-8.94l1.97-3.38a1.1 1.1 0 0 0-1.91-1.11ZM6.49 15.86a1.31 1.31 0 1 1 0-2.62 1.31 1.31 0 0 1 0 2.62Zm11.02 0a1.31 1.31 0 1 1 0-2.62 1.31 1.31 0 0 1 0 2.62Z" />
    </svg>
  );
}

export function FlashlightsHomePage({ basePath = '/flashlights' }) {
  return (
    <FlashlightsPageFrame basePath={basePath} currentPage="home">
      <header className="flashlights-hub-hero">
        <p className="flashlights-singer__eyebrow">Singer resource hub</p>
        <h1 id="flashlights-home-title" aria-label="Flashlights in the Dark">
          <span aria-hidden="true">Flashlights</span>
          <span aria-hidden="true">in the Dark</span>
        </h1>
        <p className="flashlights-singer__lede">
          Practice your part, prepare your phone, and find the latest singer-facing information for
          Jon D. Nelson’s work for voices, distributed sound, and coordinated light.
        </p>
      </header>

      <section className="flashlights-hub-feature" aria-labelledby="current-demo-title">
        <div>
          <p className="flashlights-singer__eyebrow">Current presentation</p>
          <h2 id="current-demo-title">Flashlights in motion</h2>
          <p>
            The public demonstration is still being prepared with captions and a transcript. Check
            its current availability here without loading video automatically.
          </p>
        </div>
        <a className="flashlights-hub-feature__link" href={`${resourcePath(basePath, 'videos')}#presentation`}>
          View demo status <span aria-hidden="true">→</span>
        </a>
      </section>

      <a className="flashlights-hub-browse" href={resourcePath(basePath, 'documentation')}>
        <span>Browse all singer resources</span>
        <span aria-hidden="true">→</span>
      </a>

      <section className="flashlights-hub-quick" aria-label="Quick resources">
        <a className="flashlights-hub-quick__card" href={`${resourcePath(basePath, 'documentation')}#warm-ups`}>
          <span className="flashlights-hub-quick__icon" aria-hidden="true">Do</span>
          <span>Warm-ups &amp; chromatic solfège</span>
          <small>Open the singer reference</small>
        </a>
        <a className="flashlights-hub-quick__card" href={resourcePath(basePath, 'practice')}>
          <span className="flashlights-hub-quick__icon" aria-hidden="true">♪</span>
          <span>Part-specific practice tracks</span>
          <small>Seven tracks available now</small>
        </a>
      </section>

      <section className="flashlights-hub-downloads" aria-labelledby="download-app-title">
        <div className="flashlights-hub-section-heading">
          <p className="flashlights-singer__eyebrow">Performance companion</p>
          <h2 id="download-app-title">Download or update the Flashlights app</h2>
          <p>Use these permanent links on the phone or tablet you will carry in rehearsal.</p>
        </div>
        <div className="flashlights-hub-download-grid">
          <a className="flashlights-platform-card" href={IOS_DOWNLOAD_URL}>
            <AppleMark />
            <span>
              <strong>Apple devices</strong>
              <small>iPhone &amp; iPad · TestFlight access may be limited</small>
            </span>
            <span className="flashlights-platform-card__action">Download or update</span>
          </a>
          <a className="flashlights-platform-card" href={ANDROID_DOWNLOAD_URL}>
            <AndroidMark />
            <span>
              <strong>Android</strong>
              <small>Google Play testing · sign-in required</small>
            </span>
            <span className="flashlights-platform-card__action">Download or update</span>
          </a>
        </div>
      </section>

      <section className="flashlights-hub-lower" aria-label="About the performance and earlier resources">
        <article className="flashlights-hub-lower__card">
          <p className="flashlights-singer__eyebrow">Before rehearsal</p>
          <h2>What your phone does</h2>
          <p>
            During the piece, a production-controlled app coordinates the phone’s light and assigned
            audio over a closed local Wi-Fi network. It does not listen to your singing.
          </p>
          <a className="flashlights-singer__text-link" href={`${resourcePath(basePath, 'documentation')}#electronics`}>
            Read the electronics guide
          </a>
        </article>
        <article className="flashlights-hub-lower__card flashlights-hub-lower__card--legacy">
          <p className="flashlights-singer__eyebrow">Archive &amp; advanced tools</p>
          <h2>Earlier Flashlights resources</h2>
          <p>
            Previous rehearsal tracks, the 13-part mixer, and legacy project links remain available
            for reference. Your director’s current materials take precedence.
          </p>
          <a className="flashlights-singer__text-link" href={`${resourcePath(basePath, 'documentation')}#legacy`}>
            Visit legacy resources
          </a>
        </article>
      </section>

      <p className="flashlights-hub-permanent-note">
        <strong>Bookmark or print:</strong> keex.ai/flashlights is the permanent public address for
        this evolving resource hub.
      </p>
    </FlashlightsPageFrame>
  );
}

export default FlashlightsHomePage;
