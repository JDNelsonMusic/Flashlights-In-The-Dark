import React, { useState } from 'react';
import { FlashlightsPageFrame, ResourceStatus } from './FlashlightsPageFrame';
import {
  flashlightsResourceManifest,
  validateFlashlightsResourceManifest,
} from './resourceManifest';

const VIDEO_SECTIONS = [
  {
    key: 'warmUps',
    sectionId: 'warm-ups',
    eyebrow: 'Prepare your voice',
    heading: 'Warm up with Clare',
    placeholderMark: 'C',
    comingSoon: 'Warm-up videos coming soon',
    placeholderCopy:
      'No videos are public yet. They will be activated only after explicit public-exposure approval, caption review, and complete transcripts.',
  },
  {
    key: 'presentation',
    sectionId: 'presentation',
    eyebrow: 'See the whole piece',
    heading: 'Watch the presentation',
    placeholderMark: '▶',
    comingSoon: 'Presentation video coming soon',
    placeholderCopy:
      'The unlisted demonstration is not approved for this public page yet. When it is ready, it will use a click-to-load, non-autoplay player with captions and a transcript.',
  },
];

const videosForResource = (resource) => {
  if (resource.media?.kind === 'youtube-video-collection') return resource.media.items;
  return [resource];
};

function VideoChoice({ video, isActive, onSelect }) {
  const playerId = `video-player-${video.id}`;
  return (
    <article className={`flashlights-video-choice${isActive ? ' flashlights-video-choice--active' : ''}`}>
      <h3>{video.label}</h3>
      <p>Captions and transcript verified.</p>
      <div className="flashlights-track__actions">
        <button
          className="flashlights-singer__button flashlights-singer__button--primary"
          type="button"
          aria-expanded={isActive}
          aria-controls={playerId}
          onClick={() => onSelect(isActive ? null : video.id)}
        >
          {isActive ? `Close ${video.label} player` : `Play ${video.label}`}
        </button>
        <a
          className="flashlights-singer__button flashlights-singer__button--secondary"
          href={video.url}
          target="_blank"
          rel="noreferrer"
        >
          Open on YouTube <span className="flashlights-singer__new-window">(new tab)</span>
        </a>
        <a className="flashlights-singer__text-link" href={video.media.transcript.url}>
          Read the verified transcript
        </a>
      </div>
      <div id={playerId}>
        {isActive ? (
          <div className="flashlights-track__player">
            <iframe
              src={`https://${video.media.privacyEnhancedEmbedHost}/embed/${video.media.youtubeId}?rel=0`}
              title={`${video.label} video`}
              loading="lazy"
              referrerPolicy="strict-origin-when-cross-origin"
              allow="accelerometer; encrypted-media; gyroscope; picture-in-picture"
              allowFullScreen
            />
            <p>If the player does not work, use the direct YouTube link above.</p>
          </div>
        ) : null}
      </div>
    </article>
  );
}

function VideoSection({ section, resource, activeVideoId, onSelect }) {
  const isReady = resource.status === 'ready';
  const videos = isReady ? videosForResource(resource) : [];

  return (
    <section
      id={section.sectionId}
      className="flashlights-singer__paper-panel flashlights-singer__video-resource"
      aria-labelledby={`${section.sectionId}-title`}
    >
      <div className="flashlights-singer__placeholder-mark" aria-hidden="true">
        {section.placeholderMark}
      </div>
      <div>
        <p className="flashlights-singer__eyebrow">{section.eyebrow}</p>
        <h2 id={`${section.sectionId}-title`}>{section.heading}</h2>
        {isReady ? (
          <p className="flashlights-singer__ready">
            {videos.length === 1 ? 'Video ready' : `${videos.length} videos ready`}
          </p>
        ) : (
          <ResourceStatus>{section.comingSoon}</ResourceStatus>
        )}

        {isReady ? (
          <>
            <p>
              Each approved video uses a privacy-enhanced player. It loads only after you choose Play
              and never starts automatically.
            </p>
            <div className="flashlights-video-choices">
              {videos.map((video) => (
                <VideoChoice
                  key={video.id}
                  video={video}
                  isActive={activeVideoId === video.id}
                  onSelect={onSelect}
                />
              ))}
            </div>
          </>
        ) : (
          <p>{section.placeholderCopy}</p>
        )}
      </div>
    </section>
  );
}

export function FlashlightsVideosPage({
  basePath = '/flashlights',
  resourceManifest = flashlightsResourceManifest,
}) {
  validateFlashlightsResourceManifest(resourceManifest);
  const [activeVideoId, setActiveVideoId] = useState(null);

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
        {VIDEO_SECTIONS.map((section) => (
          <VideoSection
            key={section.key}
            section={section}
            resource={resourceManifest.resources[section.key]}
            activeVideoId={activeVideoId}
            onSelect={setActiveVideoId}
          />
        ))}
      </div>
    </FlashlightsPageFrame>
  );
}

export default FlashlightsVideosPage;
