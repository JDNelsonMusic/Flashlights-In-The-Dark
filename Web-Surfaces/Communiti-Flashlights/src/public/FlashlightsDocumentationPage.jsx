import React from 'react';
import { FlashlightsPageFrame, ResourceStatus, resourcePath } from './FlashlightsPageFrame';

const SOLFEGE_ASCENDING = 'Do · Di · Re · Ri · Mi · Fa · Fi · Sol · Si · La · Li · Ti · Do';
const SOLFEGE_DESCENDING = 'Do · Ti · Te · La · Le · Sol · Se · Fa · Mi · Me · Re · Ra · Do';

export function FlashlightsDocumentationPage({ basePath = '/flashlights' }) {
  return (
    <FlashlightsPageFrame basePath={basePath} currentPage="resources">
      <header className="flashlights-singer__page-heading flashlights-resources-heading">
        <p className="flashlights-singer__eyebrow">Singer guide</p>
        <h1>All singer resources</h1>
        <p className="flashlights-singer__lede">
          Choose the smallest tool that helps today, then return as the score, videos, and rehearsal
          guidance continue to evolve.
        </p>
      </header>

      <section className="flashlights-singer__section flashlights-resources-now" aria-labelledby="available-now-title">
        <div className="flashlights-singer__section-heading">
          <p className="flashlights-singer__eyebrow">Start here</p>
          <h2 id="available-now-title">Current resources</h2>
          <p>
            Available now describes public access. Some rehearsal materials may reflect an earlier
            score edition; confirm the current form with your director.
          </p>
        </div>
        <div className="flashlights-singer__documentation-grid">
          <article className="flashlights-singer__card flashlights-singer__card--ready">
            <h3>Part-specific practice</h3>
            <p className="flashlights-singer__ready">Available now · seven tracks</p>
            <p>
              These February 2026 recordings are the currently public set. Choose the Shadow
              Chorus, Light Chorus, or complete ensemble.
            </p>
            <a className="flashlights-singer__text-link" href={resourcePath(basePath, 'practice')}>
              Choose a practice track
            </a>
          </article>
          <article className="flashlights-singer__card flashlights-singer__card--ready">
            <h3>Flashlights mobile app</h3>
            <p className="flashlights-singer__ready">Apple &amp; Android</p>
            <p>Install or update the performance companion before your first technical rehearsal.</p>
            <a className="flashlights-singer__text-link" href={resourcePath(basePath, 'install')}>
              Open installation help
            </a>
          </article>
          <article className="flashlights-singer__card">
            <h3>Formal score</h3>
            <ResourceStatus>Score PDF coming soon</ResourceStatus>
            <p>The final approved 12-page reader-order booklet will appear on the score page.</p>
            <a className="flashlights-singer__text-link" href={resourcePath(basePath, 'score')}>
              Read score details
            </a>
          </article>
          <article className="flashlights-singer__card">
            <h3>Guided videos</h3>
            <ResourceStatus>Captions &amp; transcript review</ResourceStatus>
            <p>See the honest availability status for guided warm-ups and the current presentation.</p>
            <a className="flashlights-singer__text-link" href={resourcePath(basePath, 'videos')}>
              Check video availability
            </a>
          </article>
        </div>
      </section>

      <section id="warm-ups" className="flashlights-singer__section flashlights-resource-reference" aria-labelledby="warm-ups-title">
        <div className="flashlights-singer__section-heading">
          <p className="flashlights-singer__eyebrow">Text reference</p>
          <h2 id="warm-ups-title">Warm-ups &amp; chromatic solfège</h2>
        </div>
        <p>
          Begin in a comfortable key and move only through a pain-free range. Keep the vowels unified,
          release the jaw, and let the semitone motion stay even rather than loud.
        </p>
        <dl className="flashlights-solfege">
          <div>
            <dt>Ascending chromatic syllables</dt>
            <dd>{SOLFEGE_ASCENDING}</dd>
          </div>
          <div>
            <dt>Descending chromatic syllables</dt>
            <dd>{SOLFEGE_DESCENDING}</dd>
          </div>
        </dl>
        <p className="flashlights-resource-reference__note">
          Clare’s guided warm-up videos will be added only after public approval, verified captions,
          and complete transcripts.
        </p>
      </section>

      <section id="electronics" className="flashlights-singer__section flashlights-resource-reference" aria-labelledby="electronics-title">
        <div className="flashlights-singer__section-heading">
          <p className="flashlights-singer__eyebrow">Technical essentials</p>
          <h2 id="electronics-title">How the performance electronics work</h2>
        </div>
        <p>
          Each assigned phone is a small lighting and audio endpoint. The conductor console sends
          synchronized cues over the production’s dedicated, closed local Wi-Fi network.
        </p>
        <ul className="flashlights-resource-checklist">
          <li>
            Bring only the production-assigned or approved device, fully charged, plus its cable.
            Devices used for light cues must have a tested rear torch.
          </li>
          <li>Install the current app build before rehearsal and keep the app open in the foreground.</li>
          <li>Join only the network supplied by the production team; no Bluetooth pairing is used.</li>
          <li>Allow local-network access and camera access. Camera permission controls the rear torch only.</li>
          <li>The performance app does not record or listen to your singing, and normal use does not require microphone access.</li>
          <li>Leave cueing to the conductor or technical team once your device has passed sound and light check.</li>
        </ul>
        <aside className="flashlights-resource-advisory" aria-labelledby="lighting-advisory-title">
          <h3 id="lighting-advisory-title">Lighting accessibility</h3>
          <p>
            The piece uses bright, changing phone lights. Tell the production team in advance about
            photosensitivity, migraine, vision, sensory, or other access needs so placement and an
            appropriate participation plan can be arranged. Never aim the torch directly into anyone’s eyes.
          </p>
        </aside>
      </section>

      <section id="legacy" className="flashlights-singer__section flashlights-legacy" aria-labelledby="legacy-title">
        <div className="flashlights-singer__section-heading">
          <p className="flashlights-singer__eyebrow">Archive &amp; advanced tools</p>
          <h2 id="legacy-title">Earlier Flashlights resources</h2>
          <p>
            These remain useful for context and independent study, but they may reflect earlier
            scoring, voicing, electronics, or rehearsal decisions. Follow your director’s current materials.
          </p>
        </div>
        <div className="flashlights-legacy__links">
          <a href={resourcePath(basePath, 'practice')}>
            <strong>February 2026 rehearsal tracks</strong>
            <span>Seven part and ensemble videos</span>
          </a>
          <a href={resourcePath(basePath, 'mixer')}>
            <strong>Legacy 13-part mixer</strong>
            <span>Advanced stem-by-stem rehearsal control</span>
          </a>
          <a href={resourcePath(basePath, 'videos')}>
            <strong>Presentation archive status</strong>
            <span>Public-access, caption, and transcript updates</span>
          </a>
        </div>
      </section>

      <section className="flashlights-singer__section flashlights-singer__reading" aria-labelledby="practice-routine-title">
        <h2 id="practice-routine-title">A simple practice routine</h2>
        <ol>
          <li>Warm up gently before singing at full volume.</li>
          <li>Listen once while following the current text or score supplied by your director.</li>
          <li>Sing with your own part, then try the full-ensemble track.</li>
          <li>Use the mixer to lower your part and check whether you can hold it independently.</li>
        </ol>
        <p>Playback never starts automatically. Every approved practice track can also open directly on YouTube.</p>
      </section>
    </FlashlightsPageFrame>
  );
}

export { SOLFEGE_ASCENDING, SOLFEGE_DESCENDING };
export default FlashlightsDocumentationPage;
