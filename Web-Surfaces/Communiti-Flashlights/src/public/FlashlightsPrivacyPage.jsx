import React from 'react';
import { FlashlightsPageFrame } from './FlashlightsPageFrame';

export function FlashlightsPrivacyPage({ basePath = '/flashlights' }) {
  return (
    <FlashlightsPageFrame basePath={basePath}>
      <article className="flashlights-singer__privacy">
        <header className="flashlights-singer__page-heading">
          <p className="flashlights-singer__eyebrow">Companion app policy</p>
          <h1>Flashlights privacy policy</h1>
          <p><strong>Effective date:</strong> September 19, 2025</p>
          <p><strong>Developer:</strong> KEEx AI INC</p>
        </header>

        <section aria-labelledby="privacy-overview-title">
          <h2 id="privacy-overview-title">Overview</h2>
          <p>
            The Flashlights companion app supports synchronized light, audio, and local-network cues
            during controlled rehearsals and performances. This policy explains what the app processes.
          </p>
        </section>

        <section aria-labelledby="privacy-no-collection-title">
          <h2 id="privacy-no-collection-title">Information we do not collect</h2>
          <ul>
            <li>The app does not collect or store your name, email address, phone number, or location.</li>
            <li>The app does not include third-party advertising software.</li>
            <li>The app does not track people across apps or services.</li>
          </ul>
        </section>

        <section aria-labelledby="privacy-device-title">
          <h2 id="privacy-device-title">Information processed on your device</h2>
          <p>The app may temporarily use these device features when they are needed for a performance:</p>
          <ul>
            <li>The flashlight and screen brightness to show synchronized cues.</li>
            <li>The microphone, only if you explicitly enable it for a rehearsal feature.</li>
            <li>Local Wi-Fi communication to receive cues from the conductor’s console.</li>
            <li>Notifications and foreground operation to keep rehearsal cues responsive.</li>
          </ul>
          <p>
            Rehearsal audio is not stored or sent outside the closed rehearsal network. The app does
            not upload personal data to KEEx AI.
          </p>
        </section>

        <section aria-labelledby="privacy-sharing-title">
          <h2 id="privacy-sharing-title">Sharing and security</h2>
          <p>
            KEEx AI does not sell, rent, or share user data. Performance communication remains on the
            controlled local rehearsal network.
          </p>
        </section>

        <section aria-labelledby="privacy-children-title">
          <h2 id="privacy-children-title">Children’s privacy</h2>
          <p>
            The app is intended for guided rehearsal and performance use. It does not knowingly
            collect personal information from children.
          </p>
        </section>

        <section aria-labelledby="privacy-changes-title">
          <h2 id="privacy-changes-title">Changes to this policy</h2>
          <p>KEEx AI may update this policy if app features change. Updates will appear on this page.</p>
        </section>

        <section aria-labelledby="privacy-contact-title">
          <h2 id="privacy-contact-title">Contact</h2>
          <p>
            Questions about this policy can be sent to{' '}
            <a className="flashlights-singer__text-link" href="mailto:jdn@keex.ai">jdn@keex.ai</a>.
          </p>
        </section>
      </article>
    </FlashlightsPageFrame>
  );
}

export default FlashlightsPrivacyPage;
