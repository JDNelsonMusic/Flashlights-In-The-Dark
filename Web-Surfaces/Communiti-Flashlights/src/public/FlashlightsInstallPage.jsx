import React from 'react';
import { FlashlightsPageFrame } from './FlashlightsPageFrame';

const TESTFLIGHT_URL = 'https://testflight.apple.com/join/9ASp48Jj';
const GOOGLE_PLAY_URL = 'https://play.google.com/apps/internaltest/4701639500415117370';

export function FlashlightsInstallPage({ basePath = '/flashlights' }) {
  return (
    <FlashlightsPageFrame basePath={basePath}>
      <header className="flashlights-singer__page-heading">
        <p className="flashlights-singer__eyebrow">Companion app</p>
        <h1>Install Flashlights on your phone</h1>
        <p className="flashlights-singer__lede">
          Use the phone or tablet you will carry in rehearsal. The public instructions are available
          without an account; Apple or Google may ask you to sign in before installing a test build.
        </p>
      </header>

      <nav className="flashlights-install-jump" aria-label="Choose installation instructions">
        <a className="flashlights-singer__button flashlights-singer__button--primary" href="#install-ios">
          iPhone or iPad
        </a>
        <a className="flashlights-singer__button flashlights-singer__button--secondary" href="#install-android">
          Android
        </a>
      </nav>

      <div className="flashlights-singer__install-grid">
        <section id="install-ios" className="flashlights-singer__paper-panel" aria-labelledby="install-ios-title">
          <div>
            <p className="flashlights-singer__eyebrow">iPhone and iPad</p>
            <h2 id="install-ios-title">Install through TestFlight</h2>
            <ol>
              <li>Install Apple’s TestFlight app from the App Store.</li>
              <li>Return to this page on the same device and open the invitation below.</li>
              <li>In TestFlight, choose Accept, then Install.</li>
              <li>Open Flashlights and review each permission request before allowing it.</li>
            </ol>
            <a
              className="flashlights-singer__button flashlights-singer__button--primary"
              href={TESTFLIGHT_URL}
              target="_blank"
              rel="noreferrer"
            >
              Open TestFlight invitation <span className="flashlights-singer__new-window">(new tab)</span>
            </a>
          </div>
        </section>

        <section id="install-android" className="flashlights-singer__paper-panel" aria-labelledby="install-android-title">
          <div>
            <p className="flashlights-singer__eyebrow">Android</p>
            <h2 id="install-android-title">Join the Google Play test</h2>
            <ol>
              <li>Sign in to Chrome with the Google account used on your Android device.</li>
              <li>Open the internal-test page below and choose Become a tester.</li>
              <li>Choose Download it on Google Play, then Install or Update.</li>
              <li>Open Flashlights and review each permission request before allowing it.</li>
            </ol>
            <a
              className="flashlights-singer__button flashlights-singer__button--primary"
              href={GOOGLE_PLAY_URL}
              target="_blank"
              rel="noreferrer"
            >
              Join the Android internal test <span className="flashlights-singer__new-window">(new tab)</span>
            </a>
          </div>
        </section>
      </div>

      <section className="flashlights-singer__section flashlights-singer__reading" aria-labelledby="after-install-title">
        <h2 id="after-install-title">After installation</h2>
        <ul>
          <li>Keep the app updated before rehearsals and performances.</li>
          <li>Charge your device fully and bring its charging cable.</li>
          <li>Use the in-app sound check when your rehearsal leader asks.</li>
          <li>Contact your production or choir lead if the invitation says you need access.</li>
        </ul>
      </section>
    </FlashlightsPageFrame>
  );
}

export { GOOGLE_PLAY_URL, TESTFLIGHT_URL };
export default FlashlightsInstallPage;
