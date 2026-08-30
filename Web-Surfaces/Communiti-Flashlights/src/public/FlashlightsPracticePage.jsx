import React, { useState } from 'react';
import { PRACTICE_TRACKS } from './resourceManifest';
import { FlashlightsPageFrame } from './FlashlightsPageFrame';

const TRACK_GROUPS = [
  {
    id: 'shadow-chorus',
    title: 'Shadow Chorus',
    description: 'Choose Sopranos, Altos, or Baritones.',
    tracks: PRACTICE_TRACKS.filter((track) => track.chorus === 'Shadow Chorus'),
  },
  {
    id: 'light-chorus',
    title: 'Light Chorus',
    description: 'Choose the combined part that matches your section.',
    tracks: PRACTICE_TRACKS.filter((track) => track.chorus === 'Light Chorus'),
  },
  {
    id: 'full-ensemble',
    title: 'Full ensemble',
    description: 'Hear every singer together without electronics.',
    tracks: PRACTICE_TRACKS.filter((track) => track.chorus === 'Full ensemble'),
  },
];

function PracticeTrack({ track, isActive, onSelect }) {
  const playerId = `practice-player-${track.id}`;
  return (
    <article className={`flashlights-track${isActive ? ' flashlights-track--active' : ''}`}>
      <div className="flashlights-track__heading">
        <h3>{track.voice}</h3>
        <span className="flashlights-singer__ready">Ready</span>
      </div>
      <div className="flashlights-track__actions">
        <button
          className="flashlights-singer__button flashlights-singer__button--primary"
          type="button"
          aria-expanded={isActive}
          aria-controls={playerId}
          onClick={() => onSelect(isActive ? null : track.id)}
        >
          {isActive ? `Close ${track.voice} player` : `Play ${track.voice} practice track`}
        </button>
        <a
          className="flashlights-singer__button flashlights-singer__button--secondary"
          href={track.url}
          target="_blank"
          rel="noreferrer"
        >
          Open {track.voice} on YouTube
          <span className="flashlights-singer__new-window"> (new tab)</span>
        </a>
      </div>
      <div id={playerId}>
        {isActive ? (
          <div className="flashlights-track__player">
            <iframe
              src={`https://www.youtube-nocookie.com/embed/${track.youtubeId}?rel=0`}
              title={`${track.label} practice video`}
              loading="lazy"
              referrerPolicy="strict-origin-when-cross-origin"
              allow="accelerometer; encrypted-media; gyroscope; picture-in-picture"
              allowFullScreen
            />
            <p>
              If the player does not work, use the direct YouTube link above. Playback never starts
              automatically.
            </p>
          </div>
        ) : null}
      </div>
    </article>
  );
}

export function FlashlightsPracticePage({ basePath = '/flashlights' }) {
  const [activeTrackId, setActiveTrackId] = useState(null);

  return (
    <FlashlightsPageFrame basePath={basePath} currentPage="practice">
      <header className="flashlights-singer__page-heading">
        <p className="flashlights-singer__eyebrow">Seven quick-practice choices</p>
        <h1>Practice your part</h1>
        <p className="flashlights-singer__lede">
          Choose one voice part below. A privacy-enhanced YouTube player loads only after you press
          Play, and only one player stays open at a time.
        </p>
      </header>

      <div className="flashlights-practice-groups">
        {TRACK_GROUPS.map((group) => (
          <section key={group.id} className="flashlights-practice-group" aria-labelledby={`${group.id}-title`}>
            <div className="flashlights-singer__section-heading">
              <h2 id={`${group.id}-title`}>{group.title}</h2>
              <p>{group.description}</p>
            </div>
            <div className="flashlights-practice-group__tracks">
              {group.tracks.map((track) => (
                <PracticeTrack
                  key={track.id}
                  track={track}
                  isActive={activeTrackId === track.id}
                  onSelect={setActiveTrackId}
                />
              ))}
            </div>
          </section>
        ))}
      </div>
    </FlashlightsPageFrame>
  );
}

export default FlashlightsPracticePage;
