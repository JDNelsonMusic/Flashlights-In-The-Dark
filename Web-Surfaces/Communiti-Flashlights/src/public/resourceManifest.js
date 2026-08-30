const RESOURCE_STATES = new Set(['ready', 'coming-soon']);
const CAPTION_STATES = new Set([
  'not-applicable',
  'not-provided',
  'required-before-release',
  'verified',
]);

const PRACTICE_TRACK_DATA = [
  {
    id: 'shadow-sopranos',
    chorus: 'Shadow Chorus',
    voice: 'Sopranos',
    label: 'Shadow Chorus — Sopranos',
    url: 'https://youtu.be/DD_Q9AGe3Vg',
    youtubeId: 'DD_Q9AGe3Vg',
  },
  {
    id: 'shadow-altos',
    chorus: 'Shadow Chorus',
    voice: 'Altos',
    label: 'Shadow Chorus — Altos',
    url: 'https://youtu.be/8Sq4xGM-6xc',
    youtubeId: '8Sq4xGM-6xc',
  },
  {
    id: 'shadow-baritones',
    chorus: 'Shadow Chorus',
    voice: 'Baritones',
    label: 'Shadow Chorus — Baritones',
    url: 'https://youtu.be/Bwhv9A7p63M',
    youtubeId: 'Bwhv9A7p63M',
  },
  {
    id: 'light-sopranos',
    chorus: 'Light Chorus',
    voice: 'Sopranos 1–2',
    label: 'Light Chorus — Sopranos 1–2',
    url: 'https://youtu.be/Xpy339h5v4U',
    youtubeId: 'Xpy339h5v4U',
  },
  {
    id: 'light-altos',
    chorus: 'Light Chorus',
    voice: 'Altos 1–2',
    label: 'Light Chorus — Altos 1–2',
    url: 'https://youtu.be/PjMFdOPk3Zw',
    youtubeId: 'PjMFdOPk3Zw',
  },
  {
    id: 'light-tenor-bass',
    chorus: 'Light Chorus',
    voice: 'Tenor/Bass',
    label: 'Light Chorus — Tenor/Bass',
    url: 'https://youtu.be/STO9SbsjrlY',
    youtubeId: 'STO9SbsjrlY',
  },
  {
    id: 'all-voices-no-electronics',
    chorus: 'Full ensemble',
    voice: 'All voices',
    label: 'All voices without electronics',
    url: 'https://youtu.be/xEPj1p83vHY',
    youtubeId: 'xEPj1p83vHY',
  },
];

const practiceTracks = PRACTICE_TRACK_DATA.map((track) => ({
  ...track,
  status: 'ready',
  updated: '2026-02-28',
  rightsReviewRef: 'FITD-PUBLIC-2026-08-29',
  publicExposureApprovalRef: 'FITD-PUBLIC-2026-08-29',
  captionStatus: 'not-provided',
  media: {
    kind: 'youtube-video',
    provider: 'YouTube',
    privacyEnhancedEmbedHost: 'www.youtube-nocookie.com',
    autoplay: false,
    youtubeId: track.youtubeId,
  },
}));

export const flashlightsResourceManifest = {
  schemaVersion: 1,
  updated: '2026-08-29',
  rightsReviewRef: 'FITD-PUBLIC-2026-08-29',
  rightsReviewPath: 'rights/2026-08-29-public-resource-review.md',
  resources: {
    score: {
      id: 'formal-score',
      status: 'coming-soon',
      label: '12-page formal score',
      url: null,
      updated: '2026-08-29',
      rightsReviewRef: 'FITD-PUBLIC-2026-08-29',
      publicExposureApprovalRef: null,
      captionStatus: 'not-applicable',
      media: {
        kind: 'pdf',
        mimeType: 'application/pdf',
        pageCount: null,
        fileSizeBytes: null,
        pageSize: {
          name: 'US Letter',
          widthInches: 8.5,
          heightInches: 11,
        },
        readerOrder: true,
        bookletPrint: {
          sheetSize: '11×17',
          sheetCount: 3,
          duplex: true,
        },
      },
    },
    practiceTracks,
    warmUps: {
      id: 'clare-warm-ups',
      status: 'coming-soon',
      label: 'Warm up with Clare',
      url: null,
      updated: '2026-08-29',
      rightsReviewRef: 'FITD-PUBLIC-2026-08-29',
      publicExposureApprovalRef: null,
      captionStatus: 'required-before-release',
      media: {
        kind: 'youtube-video-collection',
        provider: 'YouTube',
        itemCount: 0,
        items: [],
      },
    },
    presentation: {
      id: 'presentation-demo',
      status: 'coming-soon',
      label: 'Watch the presentation',
      url: null,
      updated: '2026-08-29',
      rightsReviewRef: 'FITD-PUBLIC-2026-08-29',
      publicExposureApprovalRef: null,
      captionStatus: 'required-before-release',
      media: {
        kind: 'youtube-video',
        provider: 'YouTube',
        privacyEnhancedEmbedHost: 'www.youtube-nocookie.com',
        autoplay: false,
        youtubeId: null,
        transcriptRequired: true,
        transcript: {
          status: 'required-before-release',
          url: null,
        },
      },
    },
    mixer: {
      id: 'advanced-mixer',
      status: 'ready',
      label: 'Advanced 13-part mixer',
      url: '/flashlights/mixer',
      updated: '2026-08-29',
      rightsReviewRef: 'FITD-PUBLIC-2026-08-29',
      publicExposureApprovalRef: 'FITD-PUBLIC-2026-08-29',
      captionStatus: 'not-applicable',
      media: {
        kind: 'interactive-audio',
        trackCount: 13,
        audioFormat: 'MP3',
      },
    },
  },
};

const isIsoDate = (value) => /^\d{4}-\d{2}-\d{2}$/.test(value ?? '');
const isNonEmptyString = (value) => typeof value === 'string' && value.trim().length > 0;

const collectResources = (manifest) => {
  const resources = manifest?.resources;
  if (!resources || typeof resources !== 'object') return [];
  return [
    resources.score,
    ...(Array.isArray(resources.practiceTracks) ? resources.practiceTracks : []),
    resources.warmUps,
    resources.presentation,
    resources.mixer,
  ];
};

export function validateFlashlightsResourceManifest(manifest) {
  const errors = [];

  if (manifest?.schemaVersion !== 1) errors.push('schemaVersion must be 1');
  if (!isIsoDate(manifest?.updated)) errors.push('manifest updated must use YYYY-MM-DD');
  if (!isNonEmptyString(manifest?.rightsReviewRef)) {
    errors.push('manifest rightsReviewRef is required');
  }
  if (!isNonEmptyString(manifest?.rightsReviewPath)) {
    errors.push('manifest rightsReviewPath is required');
  }

  const resources = collectResources(manifest);
  if (resources.length !== 11 || resources.some((resource) => !resource)) {
    errors.push('manifest must contain score, seven practice tracks, warm-ups, presentation, and mixer');
  }

  const seenIds = new Set();
  for (const resource of resources.filter(Boolean)) {
    if (!isNonEmptyString(resource.id)) errors.push('every resource needs an id');
    if (seenIds.has(resource.id)) errors.push(`duplicate resource id: ${resource.id}`);
    seenIds.add(resource.id);
    if (!isNonEmptyString(resource.label)) errors.push(`${resource.id ?? 'resource'} needs a label`);
    if (!RESOURCE_STATES.has(resource.status)) {
      errors.push(`${resource.id ?? 'resource'} has an invalid status`);
    }
    if (!isIsoDate(resource.updated)) errors.push(`${resource.id ?? 'resource'} needs an update date`);
    if (!isNonEmptyString(resource.rightsReviewRef)) {
      errors.push(`${resource.id ?? 'resource'} needs a rights-review reference`);
    }
    if (!CAPTION_STATES.has(resource.captionStatus)) {
      errors.push(`${resource.id ?? 'resource'} has an invalid caption status`);
    }
    if (!resource.media || !isNonEmptyString(resource.media.kind)) {
      errors.push(`${resource.id ?? 'resource'} needs media metadata`);
    }
    if (resource.status === 'ready' && !isNonEmptyString(resource.url)) {
      errors.push(`${resource.id ?? 'resource'} is ready but has no URL`);
    }
    if (resource.status === 'ready' && !isNonEmptyString(resource.publicExposureApprovalRef)) {
      errors.push(`${resource.id ?? 'resource'} is ready but has no public-exposure approval reference`);
    }
    if (resource.status === 'coming-soon' && resource.url !== null) {
      errors.push(`${resource.id ?? 'resource'} is coming soon and must not expose a URL`);
    }
  }

  const tracks = manifest?.resources?.practiceTracks ?? [];
  if (tracks.length !== 7) errors.push('practiceTracks must contain exactly seven tracks');
  for (const track of tracks) {
    if (!isNonEmptyString(track.chorus) || !isNonEmptyString(track.voice)) {
      errors.push(`${track.id ?? 'practice track'} needs chorus and voice metadata`);
    }
    if (track.media?.youtubeId !== track.youtubeId) {
      errors.push(`${track.id ?? 'practice track'} has mismatched YouTube metadata`);
    }
    if (
      track.media?.privacyEnhancedEmbedHost !== 'www.youtube-nocookie.com' ||
      track.media?.autoplay !== false
    ) {
      errors.push(`${track.id ?? 'practice track'} needs privacy-enhanced, non-autoplay embed metadata`);
    }
    if (track.url !== `https://youtu.be/${track.youtubeId}`) {
      errors.push(`${track.id ?? 'practice track'} has an invalid direct YouTube URL`);
    }
  }

  const score = manifest?.resources?.score;
  if (score?.status === 'ready') {
    const pageSize = score.media?.pageSize;
    if (score.media?.pageCount !== 12) errors.push('a ready score must contain exactly 12 pages');
    if (
      pageSize?.name !== 'US Letter' ||
      pageSize?.widthInches !== 8.5 ||
      pageSize?.heightInches !== 11
    ) {
      errors.push('a ready score must use 8.5×11 US Letter pages');
    }
    if (!Number.isInteger(score.media?.fileSizeBytes) || score.media.fileSizeBytes <= 0) {
      errors.push('a ready score must include a positive file size');
    }
    if (score.media?.readerOrder !== true) {
      errors.push('a ready score must be supplied in reader order');
    }
    const bookletPrint = score.media?.bookletPrint;
    if (
      bookletPrint?.sheetSize !== '11×17' ||
      bookletPrint?.sheetCount !== 3 ||
      bookletPrint?.duplex !== true
    ) {
      errors.push('a ready score must document duplex booklet printing on three 11×17 sheets');
    }
    if (!score.url?.toLowerCase().endsWith('.pdf')) {
      errors.push('a ready score URL must point to a PDF');
    }
  }

  const validateReadyVideo = (videoResource, context) => {
    if (videoResource?.status !== 'ready') {
      errors.push(`${context} must be explicitly marked ready before release`);
    }
    if (!isNonEmptyString(videoResource?.id) || !isNonEmptyString(videoResource?.label)) {
      errors.push(`${context} needs an id and label before release`);
    }
    if (!isIsoDate(videoResource?.updated)) {
      errors.push(`${context} needs an update date before release`);
    }
    if (!isNonEmptyString(videoResource?.rightsReviewRef)) {
      errors.push(`${context} needs a rights-review reference before release`);
    }
    if (!isNonEmptyString(videoResource?.publicExposureApprovalRef)) {
      errors.push(`${context} needs explicit public-exposure approval before release`);
    }
    if (videoResource?.captionStatus !== 'verified') {
      errors.push(`${context} must have verified captions before release`);
    }
    if (videoResource?.media?.transcriptRequired !== true) {
      errors.push(`${context} must require a transcript before release`);
    }
    if (
      videoResource?.media?.transcript?.status !== 'verified' ||
      !isNonEmptyString(videoResource?.media?.transcript?.url)
    ) {
      errors.push(`${context} must provide an available, verified transcript before release`);
    }
    const youtubeId = videoResource?.media?.youtubeId;
    if (!/^[A-Za-z0-9_-]{11}$/.test(youtubeId ?? '')) {
      errors.push(`${context} needs a valid YouTube video ID before release`);
    }
    if (videoResource?.url !== `https://youtu.be/${youtubeId}`) {
      errors.push(`${context} needs a direct YouTube URL matching its video ID`);
    }
    if (
      videoResource?.media?.kind !== 'youtube-video' ||
      videoResource?.media?.provider !== 'YouTube' ||
      videoResource?.media?.privacyEnhancedEmbedHost !== 'www.youtube-nocookie.com' ||
      videoResource?.media?.autoplay !== false
    ) {
      errors.push(`${context} needs privacy-enhanced, non-autoplay YouTube embed metadata`);
    }
  };

  const warmUps = manifest?.resources?.warmUps;
  if (warmUps?.status === 'ready') {
    const items = warmUps.media?.items;
    if (warmUps.media?.kind !== 'youtube-video-collection' || !Array.isArray(items) || items.length === 0) {
      errors.push('clare-warm-ups must provide at least one approved video item before release');
    } else {
      if (warmUps.media.itemCount !== items.length) {
        errors.push('clare-warm-ups itemCount must match its exposed video items');
      }
      const itemIds = new Set();
      for (const item of items) {
        if (itemIds.has(item?.id)) errors.push(`duplicate warm-up video id: ${item?.id}`);
        itemIds.add(item?.id);
        validateReadyVideo(item, `warm-up video ${item?.id ?? 'item'}`);
      }
    }
    if (warmUps.captionStatus !== 'verified') {
      errors.push('clare-warm-ups collection must have verified captions before release');
    }
  }

  const presentation = manifest?.resources?.presentation;
  if (presentation?.status === 'ready') {
    validateReadyVideo(presentation, presentation.id);
  }

  if (errors.length > 0) {
    throw new Error(`Invalid Flashlights resource manifest:\n- ${errors.join('\n- ')}`);
  }

  return manifest;
}

validateFlashlightsResourceManifest(flashlightsResourceManifest);

export const PRACTICE_TRACKS = Object.freeze(
  flashlightsResourceManifest.resources.practiceTracks.map((track) => Object.freeze(track))
);

export const FLASHLIGHTS_RESOURCE_STATES = Object.freeze([...RESOURCE_STATES]);
