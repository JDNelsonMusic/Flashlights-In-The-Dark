import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import './FlashlightsInTheDarkTool.css';
import SimplePdfViewer from './SimplePdfViewer';
import FlashlightsPrivacyPolicy from './FlashlightsPrivacyPolicy';
import img2 from '../assets/FlashlightsInTheDark_MediaAssets/Doc2_MacOS_ComposerConsoleView_App_July17-2025.png';
import img3 from '../assets/FlashlightsInTheDark_MediaAssets/Doc3_flashlights_client-iOS-screenshot_July17-2025.png';
import img4 from '../assets/FlashlightsInTheDark_MediaAssets/Doc4_FlashlightsInTheDark_DraftStagePlot_July15-2025.png';
import img5 from '../assets/FlashlightsInTheDark_MediaAssets/Doc5_FlashlightsInTheDark_ScoreFormatDemo.png';
import img6 from '../assets/FlashlightsInTheDark_MediaAssets/FlashlightsInTheDark_TwinPoem_2.png';
import img7 from '../assets/FlashlightsInTheDark_MediaAssets/FITD_LightChorus_PartAndNetworkingScheme_2.png';
import measureTiming from '../assets/FlashlightsInTheDark_MediaAssets/flashlightsMeasureMap.json';
import singerScorePdf from '../assets/FlashlightsInTheDark_MediaAssets/FlashlightsInTheDark_SingerScore_23.pdf';

const resolveAssetUrl = (asset) => {
  if (!asset) return '';
  if (typeof asset === 'string') return asset;
  if (typeof asset === 'object' && 'default' in asset) return asset.default;
  return asset;
};

const FLASHLIGHTS_AUDIO_MODULES = import.meta.glob(
  '../assets/FlashlightsInTheDark_MediaAssets/FlashlightsStems_Oct16_2025/*.mp3',
  { eager: true }
);

const getAudioAssetUrl = (relativePath) => {
  const module = FLASHLIGHTS_AUDIO_MODULES[relativePath];
  if (!module) {
    console.warn(`Flashlights audio asset not found: ${relativePath}`);
    return '';
  }
  return resolveAssetUrl(module);
};

const WAVEFORM_MODULES = import.meta.glob(
  '../assets/FlashlightsInTheDark_MediaAssets/waveforms/*.json'
);

const DEFAULT_TRACK_GAIN = Math.pow(10, -6 / 20); // -6 dB from unity

const FLASHLIGHTS_MEASURE_TABLE = Array.isArray(measureTiming?.measures)
  ? measureTiming.measures
      .map((entry) => {
        const number = Number(entry?.number);
        const startSeconds = Number(entry?.startSeconds);
        const durationSeconds = Number(entry?.durationSeconds);
        return {
          number: Number.isFinite(number) ? number : null,
          startSeconds: Number.isFinite(startSeconds) ? startSeconds : null,
          endSeconds:
            Number.isFinite(startSeconds) && Number.isFinite(durationSeconds)
              ? startSeconds + durationSeconds
              : null,
          durationSeconds: Number.isFinite(durationSeconds) ? durationSeconds : null,
          tempoBpm: Number(entry?.tempoBpm) || null,
          beats: Number(entry?.beats) || null,
          beatType: Number(entry?.beatType) || null,
        };
      })
      .filter((entry) => entry.number !== null && entry.startSeconds !== null)
  : [];

const FLASHLIGHTS_MEASURE_LOOKUP = new Map(
  FLASHLIGHTS_MEASURE_TABLE.map((entry) => [entry.number, entry])
);

const deriveMeasureDurationSeconds = (entry) => {
  if (!entry) return null;
  if (Number.isFinite(entry.durationSeconds)) return entry.durationSeconds;
  const tempo = Number(entry?.tempoBpm);
  const beats = Number(entry?.beats);
  const beatType = Number(entry?.beatType);
  if (!Number.isFinite(tempo) || !Number.isFinite(beats) || !Number.isFinite(beatType)) {
    return null;
  }
  const secondsPerBeat = 60 / tempo;
  const quarterNoteMultiplier = 4 / (beatType || 4);
  return secondsPerBeat * beats * quarterNoteMultiplier;
};

const COUNT_IN_MEASURES = 3;
const COUNT_IN_SECONDS = (() => {
  const measureOne = FLASHLIGHTS_MEASURE_LOOKUP.get(1);
  const measureDuration = deriveMeasureDurationSeconds(measureOne);
  if (!Number.isFinite(measureDuration)) return 0;
  return Math.max(0, COUNT_IN_MEASURES * measureDuration);
})();

const FLASHLIGHTS_SCORE_DURATION =
  typeof measureTiming?.metadata?.totalDurationSeconds === 'number'
    ? measureTiming.metadata.totalDurationSeconds
    : null;

const FLASHLIGHTS_REFERENCE_DURATION =
  FLASHLIGHTS_SCORE_DURATION != null ? FLASHLIGHTS_SCORE_DURATION + COUNT_IN_SECONDS : null;

const FLASHLIGHTS_STEMS = Object.freeze([
  {
    id: '1',
    waveformId: '1',
    label: 'Sopranos — Parts 1 & 2',
    shortLabel: 'Sop 1-2',
    title: 'Sopranos 1-2',
    family: 'Sopranos',
    accent: 'soprano',
    src: getAudioAssetUrl('../assets/FlashlightsInTheDark_MediaAssets/FlashlightsStems_Oct16_2025/1_Sop1-2.mp3'),
  },
  {
    id: '2',
    waveformId: '2',
    label: 'Altos — Parts 1 & 2',
    shortLabel: 'Alto 1-2',
    title: 'Altos 1-2',
    family: 'Altos',
    accent: 'alto',
    src: getAudioAssetUrl('../assets/FlashlightsInTheDark_MediaAssets/FlashlightsStems_Oct16_2025/2_Alto1-2.mp3'),
  },
  {
    id: '3',
    waveformId: '3',
    label: 'Tenors — Parts 1 & 2',
    shortLabel: 'Tenor 1-2',
    title: 'Tenors 1-2',
    family: 'Tenors',
    accent: 'tenor',
    src: getAudioAssetUrl('../assets/FlashlightsInTheDark_MediaAssets/FlashlightsStems_Oct16_2025/3_Ten1-2.mp3'),
  },
  {
    id: '4',
    waveformId: '4',
    label: 'Soprano 3',
    shortLabel: 'Sop 3',
    title: 'Soprano 3',
    family: 'Sopranos',
    accent: 'soprano',
    src: getAudioAssetUrl('../assets/FlashlightsInTheDark_MediaAssets/FlashlightsStems_Oct16_2025/4_Sop3.mp3'),
  },
  {
    id: '5',
    waveformId: '5',
    label: 'Soprano 4',
    shortLabel: 'Sop 4',
    title: 'Soprano 4',
    family: 'Sopranos',
    accent: 'soprano',
    src: getAudioAssetUrl('../assets/FlashlightsInTheDark_MediaAssets/FlashlightsStems_Oct16_2025/5_Sop4.mp3'),
  },
  {
    id: '6',
    waveformId: '6',
    label: 'Soprano 5',
    shortLabel: 'Sop 5',
    title: 'Soprano 5',
    family: 'Sopranos',
    accent: 'soprano',
    src: getAudioAssetUrl('../assets/FlashlightsInTheDark_MediaAssets/FlashlightsStems_Oct16_2025/6_Sop5.mp3'),
  },
  {
    id: '7',
    waveformId: '7',
    label: 'Alto 3',
    shortLabel: 'Alto 3',
    title: 'Alto 3',
    family: 'Altos',
    accent: 'alto',
    src: getAudioAssetUrl('../assets/FlashlightsInTheDark_MediaAssets/FlashlightsStems_Oct16_2025/7_Alto3.mp3'),
  },
  {
    id: '8',
    waveformId: '8',
    label: 'Alto 4',
    shortLabel: 'Alto 4',
    title: 'Alto 4',
    family: 'Altos',
    accent: 'alto',
    src: getAudioAssetUrl('../assets/FlashlightsInTheDark_MediaAssets/FlashlightsStems_Oct16_2025/8_Alto4.mp3'),
  },
  {
    id: '9',
    waveformId: '9',
    label: 'Alto 5',
    shortLabel: 'Alto 5',
    title: 'Alto 5',
    family: 'Altos',
    accent: 'alto',
    src: getAudioAssetUrl('../assets/FlashlightsInTheDark_MediaAssets/FlashlightsStems_Oct16_2025/9_Alto5.mp3'),
  },
  {
    id: '10',
    waveformId: '10',
    label: 'Tenor 2',
    shortLabel: 'Tenor 2',
    title: 'Tenor 2',
    family: 'Tenors',
    accent: 'tenor',
    src: getAudioAssetUrl('../assets/FlashlightsInTheDark_MediaAssets/FlashlightsStems_Oct16_2025/10_Ten2.mp3'),
  },
  {
    id: '11',
    waveformId: '11',
    label: 'Baritone 2',
    shortLabel: 'Bar 2',
    title: 'Baritone 2',
    family: 'Baritones',
    accent: 'baritone',
    src: getAudioAssetUrl('../assets/FlashlightsInTheDark_MediaAssets/FlashlightsStems_Oct16_2025/11_Bar2.mp3'),
  },
  {
    id: '12',
    waveformId: '12',
    label: 'Bass 3',
    shortLabel: 'Bass 3',
    title: 'Bass 3',
    family: 'Basses',
    accent: 'bass',
    src: getAudioAssetUrl('../assets/FlashlightsInTheDark_MediaAssets/FlashlightsStems_Oct16_2025/12_Bass3.mp3'),
  },
  {
    id: '13',
    waveformId: '13',
    label: 'Metronome Guide',
    shortLabel: 'Metronome',
    title: 'Metronome Guide',
    family: 'Guide Track',
    accent: 'guide',
    src: getAudioAssetUrl('../assets/FlashlightsInTheDark_MediaAssets/FlashlightsStems_Oct16_2025/13_Metrenome.mp3'),
  },
]);

const FLASHLIGHTS_DEMO = getAudioAssetUrl('../assets/FlashlightsInTheDark_MediaAssets/FlashlightsStems_Oct16_2025/2025_0728_FlashlightsInTheDark_24.mp3');

const FALLBACK_WAVEFORM = Array.from({ length: 180 }, (_, index) => {
  const progress = index / 180;
  const oscillation = Math.sin(progress * Math.PI * 3.6);
  return 0.35 + Math.abs(oscillation) * 0.55;
});

const WAVEFORM_CACHE = new Map();
const WAVEFORM_PENDING = new Map();
const AUDIO_DATA_CACHE = new Map();
const AUDIO_DATA_PENDING = new Map();

const PROGRESS_FALLBACK_INTERVAL_MS = 180;


const clamp = (value, min, max) => Math.min(Math.max(value, min), max);
const MIN_SELECTION_SECONDS = 0.35;
const FLASHLIGHTS_PANEL_ID = 'flashlights-panel';
const AUTO_SCROLL_BREAKPOINT = 900;

const getTabButtonId = (key) => `flashlights-tab-${key}`;

const REHEARSAL_MEASURE_NUMBERS = Object.freeze([
  2, 11, 19, 26, 31, 38, 48, 57, 66, 71, 80, 89, 98, 104, 115, 140,
]);

const FLASHLIGHTS_REHEARSAL_MARKERS = Object.freeze(
  REHEARSAL_MEASURE_NUMBERS.map((measure) => {
    const entry = FLASHLIGHTS_MEASURE_LOOKUP.get(measure);
    if (!entry || entry.startSeconds == null) {
      return null;
    }
    return {
      measure,
      seconds: entry.startSeconds + COUNT_IN_SECONDS,
      scoreSeconds: entry.startSeconds,
      durationSeconds: entry.durationSeconds,
    };
  }).filter(Boolean)
);

const getMeasureAtSeconds = (seconds) => {
  if (!Number.isFinite(seconds) || FLASHLIGHTS_MEASURE_TABLE.length === 0) return null;
  if (seconds < -0.001) return null;
  const target = Math.max(0, seconds);
  for (let index = FLASHLIGHTS_MEASURE_TABLE.length - 1; index >= 0; index -= 1) {
    const entry = FLASHLIGHTS_MEASURE_TABLE[index];
    if (entry.startSeconds != null && target + 1e-6 >= entry.startSeconds) {
      return entry;
    }
  }
  return FLASHLIGHTS_MEASURE_TABLE[0] ?? null;
};

const describeMeasureRange = (startSeconds, endSeconds) => {
  if (!Number.isFinite(startSeconds) || !Number.isFinite(endSeconds)) {
    return null;
  }

  const normalizedStart = startSeconds - COUNT_IN_SECONDS;
  const normalizedEnd = endSeconds - COUNT_IN_SECONDS;

  const startEntry = getMeasureAtSeconds(normalizedStart);
  const endEntry = getMeasureAtSeconds(normalizedEnd - 1e-6);

  if (!startEntry && !endEntry) return null;

  const startMeasure = startEntry?.number ?? endEntry?.number ?? null;
  const endMeasure = endEntry?.number ?? startEntry?.number ?? null;

  if (startMeasure === null) return null;
  if (endMeasure === null || endMeasure === startMeasure) {
    return { start: startMeasure, end: startMeasure };
  }

  return {
    start: Math.min(startMeasure, endMeasure),
    end: Math.max(startMeasure, endMeasure),
  };
};

const fetchAudioData = async (audioSrc) => {
  const sourceUrl = resolveAssetUrl(audioSrc);
  if (!sourceUrl) throw new Error('Missing audio source');

  const cached = AUDIO_DATA_CACHE.get(sourceUrl);
  if (cached) {
    return cached.slice(0);
  }

  const pending = AUDIO_DATA_PENDING.get(sourceUrl);
  if (pending) {
    const data = await pending;
    return data.slice(0);
  }

  const fetchPromise = (async () => {
    const response = await fetch(sourceUrl);
    if (!response.ok) {
      throw new Error(`Failed to load audio asset: ${response.status}`);
    }
    const arrayBuffer = await response.arrayBuffer();
    AUDIO_DATA_CACHE.set(sourceUrl, arrayBuffer);
    return arrayBuffer;
  })();

  AUDIO_DATA_PENDING.set(sourceUrl, fetchPromise);
  try {
    const data = await fetchPromise;
    return data.slice(0);
  } finally {
    AUDIO_DATA_PENDING.delete(sourceUrl);
  }
};

const TRANSPORT_ICONS = {
  play: (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M6 4l14 8-14 8z" />
    </svg>
  ),
  pause: (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M6 4h4v16H6zm8 0h4v16h-4z" />
    </svg>
  ),
  stop: (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M6 6h12v12H6z" />
    </svg>
  ),
  loop: (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M17 17H7a3 3 0 0 1 0-6h1v-2H7a5 5 0 0 0 0 10h10v3l4-4-4-4v3zM7 7h10a3 3 0 0 1 0 6h-1v2h1a5 5 0 0 0 0-10H7V2L3 6l4 4V7z" />
    </svg>
  ),
  toStart: (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M7 5h2v14H7V5zm12 7-9 6V6l9 6z" />
    </svg>
  ),
  toEnd: (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M15 5h2v14h-2V5zM7 5l9 7-9 7V5z" />
    </svg>
  ),
};

const decodeAudioData = (audioContext, arrayBuffer) => {
  if (audioContext.decodeAudioData.length <= 1) {
    return audioContext.decodeAudioData(arrayBuffer);
  }

  return new Promise((resolve, reject) => {
    audioContext.decodeAudioData(arrayBuffer, resolve, reject);
  });
};

function FlashlightsWaveform({ waveformId, className }) {
  const canvasRef = useRef(null);
  const [waveform, setWaveform] = useState(null);

  useEffect(() => {
    if (typeof window === 'undefined') {
      return undefined;
    }

    if (!waveformId) {
      setWaveform(null);
      return undefined;
    }

    const cacheKey = waveformId;
    const cached = WAVEFORM_CACHE.get(cacheKey);
    if (cached) {
      setWaveform(cached);
      return undefined;
    }

    let isMounted = true;

    const pending = WAVEFORM_PENDING.get(cacheKey);
    if (pending) {
      pending
        .then((data) => {
          if (!isMounted) return;
          setWaveform(Array.isArray(data) && data.length ? data : null);
        })
        .catch((error) => {
          if (!isMounted) return;
          if (error?.name !== 'AbortError') {
            console.warn('Flashlights waveform load failed', error);
          }
          setWaveform(null);
        });

      return () => {
        isMounted = false;
      };
    }

    const modulePath = `./FlashlightsInTheDark_MediaAssets/waveforms/${waveformId}.json`;
    const loader = WAVEFORM_MODULES[modulePath];

    if (!loader) {
      setWaveform(null);
      return () => {
        isMounted = false;
      };
    }

    const waveformPromise = loader()
      .then((mod) => {
        const data = Array.isArray(mod?.default) ? mod.default : mod;
        if (Array.isArray(data) && data.length) {
          return data;
        }
        return null;
      })
      .catch((error) => {
        if (error?.name !== 'AbortError') {
          console.warn('Flashlights waveform load failed', error);
        }
        return null;
      });

    WAVEFORM_PENDING.set(cacheKey, waveformPromise);

    waveformPromise
      .then((data) => {
        if (Array.isArray(data) && data.length) {
          WAVEFORM_CACHE.set(cacheKey, data);
        }
        if (isMounted) {
          setWaveform(Array.isArray(data) && data.length ? data : null);
        }
      })
      .finally(() => {
        WAVEFORM_PENDING.delete(cacheKey);
      });

    return () => {
      isMounted = false;
    };
  }, [waveformId]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const renderWaveform = () => {
      const ctx = canvas.getContext('2d');
      if (!ctx) return;

      const { width: cssWidth, height: cssHeight } = canvas.getBoundingClientRect();
      const dpr = window.devicePixelRatio || 1;
      canvas.width = Math.max(1, Math.round(cssWidth * dpr));
      canvas.height = Math.max(1, Math.round(cssHeight * dpr));

      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.scale(dpr, dpr);

      const width = cssWidth;
      const height = cssHeight;
      ctx.clearRect(0, 0, width, height);

      const backgroundGradient = ctx.createLinearGradient(0, 0, width, height);
      backgroundGradient.addColorStop(0, 'rgba(38, 0, 58, 0.95)');
      backgroundGradient.addColorStop(1, 'rgba(10, 0, 24, 0.95)');
      ctx.fillStyle = backgroundGradient;
      ctx.fillRect(0, 0, width, height);

      ctx.strokeStyle = 'rgba(255, 255, 255, 0.08)';
      ctx.lineWidth = 1;
      for (let i = 1; i < 6; i += 1) {
        const y = (height / 6) * i;
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(width, y);
        ctx.stroke();
      }

      const data = waveform && waveform.length ? waveform : FALLBACK_WAVEFORM;
      const step = width / data.length;
      const centerY = height / 2;
      const amplitude = height / 2.1;

      const strokeGradient = ctx.createLinearGradient(0, 0, width, 0);
      strokeGradient.addColorStop(0, '#5b21b6');
      strokeGradient.addColorStop(0.5, '#a855f7');
      strokeGradient.addColorStop(1, '#38bdf8');

      ctx.lineWidth = Math.max(2, step * 0.65);
      ctx.lineCap = 'round';
      ctx.strokeStyle = strokeGradient;
      ctx.shadowColor = 'rgba(88, 28, 135, 0.5)';
      ctx.shadowBlur = 16;

      ctx.beginPath();
      data.forEach((value, index) => {
        const x = index * step;
        const barHeight = Math.max(3, value * amplitude);
        ctx.moveTo(x, centerY - barHeight);
        ctx.lineTo(x, centerY + barHeight);
      });
      ctx.stroke();

      ctx.shadowBlur = 0;
    };

    renderWaveform();
    window.addEventListener('resize', renderWaveform);
    return () => window.removeEventListener('resize', renderWaveform);
  }, [waveform]);

  const canvasClassName = className
    ? `flashlights-waveform ${className}`
    : 'flashlights-waveform';

  return (
    <canvas
      ref={canvasRef}
      className={canvasClassName}
      role="presentation"
      aria-hidden="true"
    />
  );
}

function FlashlightsMultiTrackMixer() {
  const trackDefinitions = useMemo(() => FLASHLIGHTS_STEMS, []);

  const [muteState, setMuteState] = useState(() => trackDefinitions.map(() => false));
  const [soloState, setSoloState] = useState(() => trackDefinitions.map(() => false));
  const [isLoaded, setIsLoaded] = useState(false);
  const [loadError, setLoadError] = useState(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [playheadSeconds, setPlayheadSeconds] = useState(0);
  const [duration, setDuration] = useState(0);
  const [selectionDraft, setSelectionDraft] = useState(null);
  const [loopRegion, setLoopRegion] = useState(null);
  const [loopEnabled, setLoopEnabled] = useState(false);
  const [isLoadingAssets, setIsLoadingAssets] = useState(false);
  const [hasAudioContext, setHasAudioContext] = useState(false);

  const audioContextRef = useRef(null);
  const trackNodesRef = useRef([]);
  const startTimeRef = useRef(0);
  const pauseOffsetRef = useRef(0);
  const rafRef = useRef(null);
  const progressIntervalRef = useRef(null);
  const playheadRef = useRef(0);
  const muteStateRef = useRef(muteState);
  const soloStateRef = useRef(soloState);
  const isMountedRef = useRef(false);
  const isPlayingRef = useRef(false);
  const multitrackRef = useRef(null);
  const pointerStateRef = useRef({
    active: false,
    pointerId: null,
    anchorRatio: 0,
    lastRatio: 0,
  });
  const loopRegionRef = useRef(loopRegion);
  const loopActiveRef = useRef(false);
  const assetsLoadPromiseRef = useRef(null);

  useEffect(() => {
    muteStateRef.current = muteState;
  }, [muteState]);

  useEffect(() => {
    soloStateRef.current = soloState;
  }, [soloState]);

  useEffect(() => {
    isPlayingRef.current = isPlaying;
  }, [isPlaying]);

  useEffect(() => {
    loopRegionRef.current = loopRegion;
  }, [loopRegion]);

  const formatTime = useCallback((seconds) => {
    if (!Number.isFinite(seconds) || seconds < 0) return '0:00';
    const rounded = Math.max(0, Math.floor(seconds));
    const mins = Math.floor(rounded / 60);
    const secs = (rounded % 60).toString().padStart(2, '0');
    return `${mins}:${secs}`;
  }, []);

  const stopProgressTracking = useCallback(() => {
    if (rafRef.current) {
      cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
    }
    if (progressIntervalRef.current) {
      clearInterval(progressIntervalRef.current);
      progressIntervalRef.current = null;
    }
  }, []);

  const updateTrackGains = useCallback((muteOverride, soloOverride) => {
    const ctx = audioContextRef.current;
    if (!ctx) return;

    const muteValues = muteOverride ?? muteStateRef.current;
    const soloValues = soloOverride ?? soloStateRef.current;
    const soloActive = soloValues.some(Boolean);
    const now = ctx.currentTime || 0;

    trackNodesRef.current.forEach((track, index) => {
      const gainNode = track?.gainNode;
      if (!gainNode) return;

      const shouldPlay = soloActive ? soloValues[index] && !muteValues[index] : !muteValues[index];
      const target = shouldPlay ? DEFAULT_TRACK_GAIN : 0;

      if (isPlayingRef.current) {
        try {
          gainNode.gain.cancelScheduledValues(now);
          gainNode.gain.setTargetAtTime(target, now, 0.015);
        } catch (error) {
          gainNode.gain.value = target;
        }
      } else {
        gainNode.gain.value = target;
      }
    });
  }, []);

  const stopPlayback = useCallback(
    (resetOffset = false) => {
      const ctx = audioContextRef.current;
      let currentOffset = pauseOffsetRef.current;
      if (!resetOffset && ctx && isPlayingRef.current) {
        const elapsedSeconds = ctx.currentTime - startTimeRef.current;
        const safeOffset = Math.max(0, Math.min(elapsedSeconds, duration || elapsedSeconds));
        currentOffset = safeOffset;
      }
      trackNodesRef.current.forEach((track) => {
        if (track?.source) {
          try {
            track.source.onended = null;
            track.source.stop(0);
          } catch (error) {
            // ignore stop errors when tearing down sources
          }
          try {
            track.source.disconnect();
          } catch (error) {
            // ignore disconnect errors
          }
          track.source = null;
        }
      });

      stopProgressTracking();
      const targetOffset = resetOffset
        ? 0
        : Math.max(0, Math.min(currentOffset, duration || currentOffset));
      pauseOffsetRef.current = targetOffset;
      playheadRef.current = targetOffset;
      if (isMountedRef.current) {
        setPlayheadSeconds(targetOffset);
      }

      if (isMountedRef.current) setIsPlaying(false);
      isPlayingRef.current = false;
    },
    [stopProgressTracking, duration]
  );

  const updateProgress = useCallback(() => {
    const ctx = audioContextRef.current;
    if (!ctx) return;

    const elapsedSeconds = ctx.currentTime - startTimeRef.current;
    const loopRegionValue = loopRegionRef.current;
    const loopActive = loopActiveRef.current && loopRegionValue;
    const clampedElapsed = Math.max(0, elapsedSeconds);

    if (!loopActive && clampedElapsed >= duration && duration > 0) {
      if (isMountedRef.current) {
        playheadRef.current = duration;
        setPlayheadSeconds(duration);
      }
      stopPlayback();
      return;
    }

    let displayElapsed = clampedElapsed;

    if (loopActive) {
      const { start, end } = loopRegionValue;
      const loopLength = Math.max(0.01, end - start);

      if (clampedElapsed < start) {
        displayElapsed = start;
      } else if (clampedElapsed > end) {
        const cycles = Math.floor((clampedElapsed - start) / loopLength);
        if (cycles >= 1) {
          startTimeRef.current += loopLength * cycles;
          displayElapsed = clampedElapsed - loopLength * cycles;
        } else {
          displayElapsed = clampedElapsed;
        }
        displayElapsed = clamp(displayElapsed, start, end);
      } else {
        displayElapsed = clamp(clampedElapsed, start, end);
      }
    }

    const safeElapsed = Math.max(0, Math.min(displayElapsed, duration || displayElapsed));
    pauseOffsetRef.current = safeElapsed;
    if (isMountedRef.current && Math.abs(safeElapsed - playheadRef.current) > 0.0005) {
      playheadRef.current = safeElapsed;
      setPlayheadSeconds(safeElapsed);
    }
  }, [duration, stopPlayback]);

  const ensureTrackBuffer = useCallback(
    async (index) => {
      const ctx = audioContextRef.current;
      if (!ctx) throw new Error('Audio context unavailable');

      const trackNode = trackNodesRef.current[index];
      if (!trackNode) return null;

      if (trackNode.buffer) {
        return trackNode.buffer;
      }

      if (trackNode.loadingPromise) {
        return trackNode.loadingPromise;
      }

      const definition = trackDefinitions[index];
      if (!definition) return null;

      const assetUrl = resolveAssetUrl(definition.src);
      if (!assetUrl) {
        throw new Error(`Missing audio source for track ${definition.id}`);
      }

      const loadPromise = (async () => {
        const arrayBuffer = await fetchAudioData(assetUrl);
        const buffer = await decodeAudioData(ctx, arrayBuffer);
        trackNode.buffer = buffer;
        return buffer;
      })();

      trackNode.loadingPromise = loadPromise;

      try {
        const buffer = await loadPromise;
        return buffer;
      } finally {
        trackNode.loadingPromise = null;
      }
    },
    [trackDefinitions]
  );

  const ensureAllTrackBuffers = useCallback(async () => {
    const buffers = await Promise.all(
      trackDefinitions.map((_, index) => ensureTrackBuffer(index))
    );
    return buffers;
  }, [ensureTrackBuffer, trackDefinitions]);

  const loadAssets = useCallback(async () => {
    if (isLoaded) {
      const playbackDuration = trackNodesRef.current.reduce(
        (max, track) => Math.max(max, track?.buffer?.duration || 0),
        0
      );
      if (
        isMountedRef.current &&
        playbackDuration &&
        Math.abs((duration || 0) - playbackDuration) > 0.01
      ) {
        setDuration(playbackDuration);
      }
      return playbackDuration;
    }

    if (assetsLoadPromiseRef.current) {
      return assetsLoadPromiseRef.current;
    }

    const ctx = audioContextRef.current;
    if (!ctx) return null;

    if (isMountedRef.current) setIsLoadingAssets(true);
    setLoadError(null);

    const loadPromise = (async () => {
      try {
        const buffers = await ensureAllTrackBuffers();
        const validBuffers = buffers.filter(Boolean);
        const playbackDuration = validBuffers.reduce(
          (max, buffer) => Math.max(max, buffer?.duration || 0),
          0
        );

        playheadRef.current = 0;
        if (isMountedRef.current) {
          setDuration(playbackDuration);
          pauseOffsetRef.current = 0;
          setPlayheadSeconds(0);
          setIsLoaded(true);
        }

        return playbackDuration;
      } catch (error) {
        console.error('Flashlights multitrack load failed', error);
        if (isMountedRef.current) {
          setLoadError('Unable to load the individual parts. Please try again.');
          setIsLoaded(false);
        }
        throw error;
      } finally {
        if (isMountedRef.current) setIsLoadingAssets(false);
      }
    })();

    assetsLoadPromiseRef.current = loadPromise;

    try {
      return await loadPromise;
    } finally {
      assetsLoadPromiseRef.current = null;
    }
  }, [ensureAllTrackBuffers, isLoaded, duration]);

  const jumpToStart = useCallback(() => {
    stopPlayback(true);
  }, [stopPlayback]);

  const jumpToEnd = useCallback(() => {
    if (!Number.isFinite(duration) || duration <= 0) {
      stopPlayback(false);
      return;
    }
    stopPlayback(false);
    const target = duration;
    pauseOffsetRef.current = target;
    playheadRef.current = target;
    if (isMountedRef.current) {
      setPlayheadSeconds(target);
      setIsPlaying(false);
    }
  }, [duration, stopPlayback]);

  const startPlayback = useCallback(async () => {
    if (isPlayingRef.current) return;
    const ctx = audioContextRef.current;
    if (!ctx) return;

    const playbackDuration = await loadAssets();
    if (!trackNodesRef.current.some((track) => track?.buffer)) {
      console.warn('Flashlights mixer attempted playback without buffers');
      return;
    }

    if (ctx.state === 'suspended') {
      try {
        await ctx.resume();
      } catch (error) {
        console.warn('Flashlights mixer resume failed', error);
        return;
      }
    }

    const resolvedDuration = trackNodesRef.current.reduce(
      (max, track) => Math.max(max, track?.buffer?.duration || 0),
      0
    ) || playbackDuration || duration || 0;
    if (resolvedDuration > 0 && pauseOffsetRef.current > resolvedDuration) {
      pauseOffsetRef.current = 0;
      if (isMountedRef.current) {
        playheadRef.current = 0;
        setPlayheadSeconds(0);
      }
    }

    const effectiveOffset = resolvedDuration > 0 && pauseOffsetRef.current >= resolvedDuration
      ? 0
      : pauseOffsetRef.current;

    pauseOffsetRef.current = effectiveOffset;
    startTimeRef.current = ctx.currentTime - effectiveOffset;
    if (isMountedRef.current) {
      playheadRef.current = effectiveOffset;
      setPlayheadSeconds(effectiveOffset);
    }

    trackNodesRef.current.forEach((track) => {
      if (!track?.buffer) return;

      try {
        if (track.source) {
          track.source.onended = null;
          track.source.stop(0);
          track.source.disconnect();
          track.source = null;
        }
      } catch (error) {
        // ignore stale sources
      }

      const source = ctx.createBufferSource();
      const bufferDuration = track.buffer.duration || 0;
      const maxOffset = bufferDuration
        ? Math.max(0, bufferDuration - 0.05)
        : Math.max(0, resolvedDuration - 0.05);
      let startOffset = Math.min(Math.max(0, effectiveOffset), maxOffset);

      source.buffer = track.buffer;
      source.connect(track.gainNode);
      source.onended = () => {
        track.source = null;
      };

      if (loopActiveRef.current && loopRegionRef.current) {
        const loopStart = clamp(loopRegionRef.current.start, 0, bufferDuration || resolvedDuration || 0);
        const maxLoopEnd = bufferDuration || resolvedDuration || loopStart + 0.01;
        const loopEnd = clamp(
          loopRegionRef.current.end,
          loopStart + 0.01,
          Math.max(loopStart + 0.01, maxLoopEnd)
        );
        source.loop = true;
        source.loopStart = loopStart;
        source.loopEnd = loopEnd;
        startOffset = clamp(startOffset, loopStart, Math.max(loopStart, loopEnd - 0.001));
      } else {
        source.loop = false;
      }

      try {
        source.start(0, Math.max(0, startOffset));
      } catch (error) {
        console.warn('Flashlights mixer source start failed', error);
      }

      track.source = source;
    });

    updateTrackGains();
    isPlayingRef.current = true;
    if (isMountedRef.current) setIsPlaying(true);
    stopProgressTracking();
    const tick = () => {
      updateProgress();
      if (isPlayingRef.current) {
        rafRef.current = requestAnimationFrame(tick);
      } else {
        rafRef.current = null;
      }
    };
    updateProgress();
    rafRef.current = requestAnimationFrame(tick);
    progressIntervalRef.current = setInterval(() => {
      updateProgress();
    }, PROGRESS_FALLBACK_INTERVAL_MS);
  }, [duration, loadAssets, stopProgressTracking, updateTrackGains, updateProgress]);

  const pausePlayback = useCallback(() => {
    if (!isPlayingRef.current) return;
    const ctx = audioContextRef.current;
    if (!ctx) return;

    trackNodesRef.current.forEach((track) => {
      if (!track?.source) return;
      try {
        track.source.onended = null;
        track.source.stop(0);
      } catch (error) {
        // ignore stop errors during pause
      }
      try {
        track.source.disconnect();
      } catch (error) {
        // ignore disconnect errors
      }
      track.source = null;
    });

    const elapsedSeconds = ctx.currentTime - startTimeRef.current;
    const safeOffset = Math.min(Math.max(0, elapsedSeconds), duration || elapsedSeconds);
    pauseOffsetRef.current = safeOffset;
    playheadRef.current = safeOffset;
    if (isMountedRef.current) {
      setPlayheadSeconds(safeOffset);
      setIsPlaying(false);
    } else {
      setIsPlaying(false);
    }
    isPlayingRef.current = false;
    stopProgressTracking();
  }, [duration, stopProgressTracking]);

  const seekTo = useCallback(
    (nextTime, resumePlayback) => {
      if (!Number.isFinite(nextTime) || duration <= 0) return;
      const target = clamp(nextTime, 0, duration);
      const shouldResume =
        typeof resumePlayback === 'boolean' ? resumePlayback : isPlayingRef.current;
      const wasPlaying = shouldResume && isLoaded && isPlayingRef.current;

      if (wasPlaying) {
        stopPlayback(false);
      }

      pauseOffsetRef.current = target;
      playheadRef.current = target;
      if (isMountedRef.current) {
        setPlayheadSeconds(target);
      }

      if (wasPlaying) {
        startPlayback();
      }
    },
    [duration, isLoaded, startPlayback, stopPlayback]
  );

  useEffect(() => {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (!AudioContextClass) {
      setLoadError('Web Audio API not available. Please use a modern browser.');
      setIsLoaded(false);
      return undefined;
    }

    const ctx = new AudioContextClass();
    audioContextRef.current = ctx;
    isMountedRef.current = true;

    trackNodesRef.current = trackDefinitions.map(() => ({
      buffer: null,
      gainNode: ctx.createGain(),
      loadingPromise: null,
      source: null,
    }));

    trackNodesRef.current.forEach((track) => {
      if (!track?.gainNode) return;
      track.gainNode.gain.value = 0;
      track.gainNode.connect(ctx.destination);
    });

    setLoadError(null);
    setIsLoaded(false);
    setHasAudioContext(true);

    return () => {
      isMountedRef.current = false;
      stopPlayback(true);
      trackNodesRef.current.forEach((track) => {
        if (track?.gainNode) {
          try {
            track.gainNode.disconnect();
          } catch (error) {
            // ignore disconnect errors
          }
        }
      });
      stopProgressTracking();
      if (ctx && typeof ctx.close === 'function') {
        ctx.close().catch(() => {});
      }
      audioContextRef.current = null;
      assetsLoadPromiseRef.current = null;
      setHasAudioContext(false);
      setIsLoadingAssets(false);
    };
  }, [stopPlayback, stopProgressTracking, trackDefinitions, updateTrackGains]);

  useEffect(() => {
    if (!hasAudioContext || isLoaded) {
      return undefined;
    }

    loadAssets().catch((error) => {
      console.warn('Flashlights multitrack auto-load failed', error);
    });

    return undefined;
  }, [hasAudioContext, isLoaded, loadAssets]);

  useEffect(() => {
    if (typeof window === 'undefined') return undefined;

    const handleTransportKey = (event) => {
      if (event.defaultPrevented) return;
      if (event.code !== 'Space' && event.key !== ' ') return;

      const target = event.target;
      if (
        target &&
        (target.tagName === 'INPUT' ||
          target.tagName === 'TEXTAREA' ||
          target.tagName === 'SELECT' ||
          target.isContentEditable)
      ) {
        return;
      }

      event.preventDefault();
      if (isPlayingRef.current) {
        stopPlayback();
      } else {
        startPlayback();
      }
    };

    window.addEventListener('keydown', handleTransportKey);
    return () => {
      window.removeEventListener('keydown', handleTransportKey);
    };
  }, [startPlayback, stopPlayback]);

  useEffect(() => {
    const previousRegion = loopRegionRef.current;
    const sanitizedRegion =
      duration > 0 && loopRegion && loopRegion.end - loopRegion.start >= MIN_SELECTION_SECONDS
        ? {
            start: clamp(loopRegion.start, 0, duration),
            end: clamp(loopRegion.end, 0, duration),
          }
        : null;

    loopRegionRef.current = sanitizedRegion;

    if (!isLoaded) {
      loopActiveRef.current = false;
      return;
    }

    const shouldActivate = Boolean(sanitizedRegion && loopEnabled);
    const wasActive = loopActiveRef.current;
    const regionChanged =
      Boolean(previousRegion) !== Boolean(sanitizedRegion) ||
      (previousRegion && sanitizedRegion &&
        (Math.abs(previousRegion.start - sanitizedRegion.start) > 0.01 ||
          Math.abs(previousRegion.end - sanitizedRegion.end) > 0.01));

    if (shouldActivate && (!wasActive || regionChanged)) {
      const startPoint = sanitizedRegion.start;
      pauseOffsetRef.current = startPoint;
      if (isMountedRef.current) {
        setPlayheadSeconds(startPoint);
      }
      loopActiveRef.current = true;
      if (isPlayingRef.current) {
        stopPlayback(false);
      }
      startPlayback();
      return;
    }

    if (!shouldActivate && wasActive) {
      loopActiveRef.current = false;
      if (isPlayingRef.current) {
        stopPlayback(false);
        startPlayback();
      }
    }

    if (!shouldActivate) {
      loopActiveRef.current = false;
    }
  }, [duration, isLoaded, loopEnabled, loopRegion, startPlayback, stopPlayback]);

  const handleMuteToggle = (index) => {
    setMuteState((previous) => {
      const next = [...previous];
      next[index] = !previous[index];
      muteStateRef.current = next;
      updateTrackGains(next, soloStateRef.current);
      return next;
    });
  };

  const handleSoloToggle = (index) => {
    setSoloState((previous) => {
      const next = [...previous];
      next[index] = !previous[index];
      soloStateRef.current = next;
      updateTrackGains(muteStateRef.current, next);
      return next;
    });
  };

  const handleWaveformPointerDown = useCallback(
    (event) => {
      if (!isLoaded || duration <= 0) return;
      if (event.isPrimary === false) return;
      if (event.pointerType === 'mouse' && event.button !== 0) return;

      const rect = event.currentTarget.getBoundingClientRect();
      if (rect.width <= 0) return;
      const ratio = clamp((event.clientX - rect.left) / rect.width, 0, 1);

      pointerStateRef.current = {
        active: true,
        pointerId: event.pointerId,
        anchorRatio: ratio,
        lastRatio: ratio,
      };

      try {
        event.currentTarget.setPointerCapture(event.pointerId);
      } catch (error) {
        // pointer capture not supported
      }

      setSelectionDraft({ start: ratio * duration, end: ratio * duration });
      setLoopEnabled(false);
      event.preventDefault();
    },
    [duration, isLoaded]
  );

  const handleWaveformPointerMove = useCallback(
    (event) => {
      const state = pointerStateRef.current;
      if (!state.active || state.pointerId !== event.pointerId) return;

      const rect = event.currentTarget.getBoundingClientRect();
      if (rect.width <= 0) return;
      const ratio = clamp((event.clientX - rect.left) / rect.width, 0, 1);

      state.lastRatio = ratio;
      setSelectionDraft({ start: state.anchorRatio * duration, end: ratio * duration });
      event.preventDefault();
    },
    [duration]
  );

  const resetPointerState = useCallback(() => {
    pointerStateRef.current = {
      active: false,
      pointerId: null,
      anchorRatio: 0,
      lastRatio: 0,
    };
  }, []);

  const concludeSelection = useCallback(
    (event, cancelled = false) => {
      const state = pointerStateRef.current;
      if (!state.active || state.pointerId !== event.pointerId) {
        if (cancelled) resetPointerState();
        return;
      }

      if (event.currentTarget.hasPointerCapture?.(event.pointerId)) {
        event.currentTarget.releasePointerCapture(event.pointerId);
      }

      const anchorSeconds = clamp(state.anchorRatio, 0, 1) * duration;
      const endSeconds = clamp(state.lastRatio, 0, 1) * duration;
      const span = Math.abs(endSeconds - anchorSeconds);

      setSelectionDraft(null);
      resetPointerState();

      if (cancelled) return;

      if (span < MIN_SELECTION_SECONDS) {
        seekTo(endSeconds);
        return;
      }

      const startValue = Math.min(anchorSeconds, endSeconds);
      const endValue = Math.max(anchorSeconds, endSeconds);
      const clampedStart = clamp(startValue, 0, duration);
      const safeMax = duration > 0 ? Math.max(duration, clampedStart + 0.01) : clampedStart + 0.01;
      const clampedEnd = clamp(endValue, clampedStart + 0.01, safeMax);
      const boundedEnd = duration > 0 ? Math.min(clampedEnd, duration) : clampedEnd;

      if (boundedEnd <= clampedStart) {
        return;
      }

      setLoopRegion({ start: clampedStart, end: boundedEnd });
    },
    [duration, resetPointerState, seekTo]
  );

  const handleWaveformPointerUp = useCallback(
    (event) => {
      concludeSelection(event, false);
      event.preventDefault();
    },
    [concludeSelection]
  );

  const handleWaveformPointerCancel = useCallback(
    (event) => {
      concludeSelection(event, true);
    },
    [concludeSelection]
  );

  const clearLoopSelection = useCallback(() => {
    setLoopRegion(null);
    setSelectionDraft(null);
    setLoopEnabled(false);
  }, []);

  const handleLoopToggle = useCallback(() => {
    if (!loopRegion || loopRegion.end - loopRegion.start < MIN_SELECTION_SECONDS) return;
    setLoopEnabled((prev) => !prev);
  }, [loopRegion]);

  const soloActive = soloState.some(Boolean);
  const progressPercent = duration ? Math.min(100, (playheadSeconds / duration) * 100) : 0;
  const playheadPercent = Number.isFinite(duration) && duration > 0 ? progressPercent : 0;
  const loopSelectionReady = Boolean(
    loopRegion && loopRegion.end - loopRegion.start >= MIN_SELECTION_SECONDS
  );
  const loopActive = loopSelectionReady && loopEnabled;
  const timelineDuration =
    Number.isFinite(duration) && duration > 0
      ? duration
      : Number.isFinite(FLASHLIGHTS_REFERENCE_DURATION)
        ? FLASHLIGHTS_REFERENCE_DURATION
        : 0;
  const rehearsalMarkers = useMemo(() => {
    if (!timelineDuration || !FLASHLIGHTS_REHEARSAL_MARKERS.length) return [];
    const maxSeconds = timelineDuration + 5;
    return FLASHLIGHTS_REHEARSAL_MARKERS.filter(
      (marker) => Number.isFinite(marker?.seconds) && marker.seconds <= maxSeconds
    ).map((marker) => {
      const percent = timelineDuration
        ? clamp((marker.seconds / timelineDuration) * 100, 0, 100)
        : 0;
      return {
        measure: marker.measure,
        seconds: marker.seconds,
        position: percent,
        display: `m. ${marker.measure}`,
      };
    });
  }, [timelineDuration]);
  const activeRehearsalMeasure = useMemo(() => {
    if (!rehearsalMarkers.length) return null;
    let current = null;
    for (let index = 0; index < rehearsalMarkers.length; index += 1) {
      const marker = rehearsalMarkers[index];
      const nextMarker = rehearsalMarkers[index + 1];
      const hasStarted = playheadSeconds >= marker.seconds;
      const beforeNext = !nextMarker || playheadSeconds < nextMarker.seconds;
      if (hasStarted && beforeNext) {
        current = marker.measure;
        break;
      }
    }
    return current;
  }, [playheadSeconds, rehearsalMarkers]);
  const measureTicks = useMemo(() => {
    if (!timelineDuration || !FLASHLIGHTS_MEASURE_TABLE.length) return [];
    const labelMeasures = new Set(REHEARSAL_MEASURE_NUMBERS);
    labelMeasures.add(1);
    FLASHLIGHTS_MEASURE_TABLE.forEach((entry) => {
      if (entry.number % 4 === 0) labelMeasures.add(entry.number);
    });
    const ticks = FLASHLIGHTS_MEASURE_TABLE.filter(
      (entry) => Number.isFinite(entry.startSeconds)
    ).map((entry) => {
      const audioStartSeconds = entry.startSeconds + COUNT_IN_SECONDS;
      const left = timelineDuration
        ? clamp((audioStartSeconds / timelineDuration) * 100, 0, 100)
        : 0;
      const width =
        Number.isFinite(entry.endSeconds) && timelineDuration
          ? clamp(((entry.endSeconds - entry.startSeconds) / timelineDuration) * 100, 0, 100 - left)
          : 0;
      return {
        measure: entry.number,
        leftPercent: left,
        widthPercent: width,
        isLabel: labelMeasures.has(entry.number),
        label: `m. ${entry.number}`,
      };
    });
    if (COUNT_IN_SECONDS > 0 && timelineDuration > 0) {
      const countInLabel = COUNT_IN_MEASURES === 1
        ? 'Count-in (1 bar)'
        : `Count-in (${COUNT_IN_MEASURES} bars)`;
      ticks.unshift({
        measure: 'count-in',
        leftPercent: 0,
        widthPercent: clamp((COUNT_IN_SECONDS / timelineDuration) * 100, 0, 100),
        isLabel: true,
        label: countInLabel,
        isCountIn: true,
      });
    }
    return ticks;
  }, [timelineDuration]);
  const activeSelection = selectionDraft ?? loopRegion;
  let selectionStyle = null;
  let selectionBounds = null;
  if (activeSelection && duration > 0) {
    const startSeconds = Math.min(activeSelection.start, activeSelection.end);
    const endSeconds = Math.max(activeSelection.start, activeSelection.end);
    const span = Math.max(0, endSeconds - startSeconds);
    const startPercent = clamp((startSeconds / duration) * 100, 0, 100);
    if (span > 0) {
      const widthPercent = clamp((span / duration) * 100, 0, 100 - startPercent);
      selectionStyle = {
        left: `${startPercent}%`,
        width: `${widthPercent}%`,
        minWidth: '4px',
      };
      selectionBounds = { startSeconds, endSeconds };
    } else if (selectionDraft) {
      selectionStyle = {
        left: `${startPercent}%`,
        width: '0%',
        minWidth: '4px',
      };
    }
  }
  const selectionSummary = selectionBounds
    ? (() => {
        const { startSeconds, endSeconds } = selectionBounds;
        const measureRange = describeMeasureRange(startSeconds, endSeconds);
        const timeLabel = `${formatTime(startSeconds)} – ${formatTime(endSeconds)}`;
        if (!measureRange) {
          if (endSeconds <= COUNT_IN_SECONDS + 0.01) {
            return `Loop count-in (${timeLabel})`;
          }
          if (startSeconds < COUNT_IN_SECONDS && endSeconds > COUNT_IN_SECONDS) {
            const firstMeasure = getMeasureAtSeconds(0);
            if (firstMeasure?.number) {
              return `Loop count-in → m. ${firstMeasure.number} (${timeLabel})`;
            }
          }
          return `Loop ${timeLabel}`;
        }
        if (measureRange.start === measureRange.end) {
          return `Loop m. ${measureRange.start} (${timeLabel})`;
        }
        return `Loop m. ${measureRange.start}–${measureRange.end} (${timeLabel})`;
      })()
    : null;
  const assetsAreLoading = isLoadingAssets;
  const statusLabel = !isLoaded
    ? loadError
      ? 'Assets unavailable'
      : assetsAreLoading
        ? 'Loading assets…'
        : 'Ready to load'
    : isPlaying
      ? 'Playing'
      : playheadSeconds > 0 && playheadSeconds < duration
        ? 'Paused'
        : 'Ready';
  const statusClassName = assetsAreLoading
    ? 'flashlights-status-label flashlights-status-label--loading'
    : 'flashlights-status-label';

  return (
    <div className="flashlights-multitrack" aria-live="polite" ref={multitrackRef}>
      <div className="flashlights-multitrack-guidance" role="note">
        <p>
          Click anywhere in a waveform—or drag to highlight a span—to jump straight to the measure you
          want to rehearse. Keep an eye on the rehearsal markers above for quick landmarks. Use the
          <strong>Solo</strong> button to spotlight an individual part, and hit <strong>Mute</strong> when you
          need that stem out of the blend.
        </p>
      </div>
      <div className="flashlights-transport">
        <div className="flashlights-transport-group">
          {assetsAreLoading && (
            <span className={`${statusClassName} flashlights-status-label--inline`}>{statusLabel}</span>
          )}
          <button
            type="button"
            className="flashlights-transport-button ghost"
            onClick={jumpToStart}
            disabled={!isLoaded}
            title="Back to beginning"
            aria-label="Back to beginning"
          >
            <span className="flashlights-transport-icon">{TRANSPORT_ICONS.toStart}</span>
            <span className="flashlights-transport-text">Beginning</span>
          </button>
          <button
            type="button"
            className="flashlights-transport-button"
            onClick={startPlayback}
            disabled={assetsAreLoading || isPlaying || !hasAudioContext}
          >
            <span className="flashlights-transport-icon">{TRANSPORT_ICONS.play}</span>
            <span className="flashlights-transport-text">Play</span>
          </button>
          <button
            type="button"
            className="flashlights-transport-button"
            onClick={pausePlayback}
            disabled={!isLoaded || !isPlaying}
          >
            <span className="flashlights-transport-icon">{TRANSPORT_ICONS.pause}</span>
            <span className="flashlights-transport-text">Pause</span>
          </button>
          <button
            type="button"
            className="flashlights-transport-button"
            onClick={() => stopPlayback()}
            disabled={!isLoaded || (playheadSeconds <= 0.0001 && !isPlaying)}
          >
            <span className="flashlights-transport-icon">{TRANSPORT_ICONS.stop}</span>
            <span className="flashlights-transport-text">Stop</span>
          </button>
          <button
            type="button"
            className="flashlights-transport-button ghost"
            onClick={jumpToEnd}
            disabled={!isLoaded || !Number.isFinite(duration) || duration <= 0}
            title="Skip to end"
            aria-label="Skip to end"
          >
            <span className="flashlights-transport-icon">{TRANSPORT_ICONS.toEnd}</span>
            <span className="flashlights-transport-text">End</span>
          </button>
        </div>
        <div className="flashlights-transport-group flashlights-loop-controls">
          <button
            type="button"
            className={loopActive ? 'flashlights-transport-button loop active' : 'flashlights-transport-button loop'}
            onClick={handleLoopToggle}
            disabled={!loopSelectionReady || !isLoaded}
            aria-pressed={loopActive}
            title={loopSelectionReady ? 'Loop highlighted section' : 'Select a section to enable looping'}
          >
            <span className="flashlights-transport-icon">{TRANSPORT_ICONS.loop}</span>
            <span className="flashlights-transport-text">{loopActive ? 'Looping' : 'Loop Selection'}</span>
          </button>
          <button
            type="button"
            className="flashlights-transport-button ghost"
            onClick={clearLoopSelection}
            disabled={!loopRegion}
            title="Clear highlighted selection"
          >
            <span className="flashlights-transport-text">Clear Selection</span>
          </button>
        </div>
        <div className="flashlights-transport-status">
          <span className="flashlights-transport-time">{formatTime(playheadSeconds)} / {formatTime(duration)}</span>
          {!assetsAreLoading && <span className={statusClassName}>{statusLabel}</span>}
          {loopActive && <span className="flashlights-status-chip loop">Looping</span>}
          {soloActive && <span className="flashlights-status-chip">Solo active</span>}
        </div>
      </div>
      <div className="flashlights-timeline-grid">
        <div className="flashlights-timeline-spacer" aria-hidden="true" />
        <div className="flashlights-timeline-track">
          <div className="flashlights-timeline-surface">
            <div className="flashlights-transport-progress">
              <div className="flashlights-progress-bar">
                <div className="flashlights-progress-bar-fill" style={{ width: `${progressPercent}%` }} />
              </div>
              {selectionStyle && (
                <div className="flashlights-progress-selection" style={selectionStyle} aria-hidden="true" />
              )}
            </div>
            <div className="flashlights-measure-grid" aria-hidden="true">
              {measureTicks
                .filter((tick) => !tick.isCountIn)
                .map((tick) => (
                  <div
                    key={`tick-${tick.measure}`}
                    className={tick.isLabel ? 'flashlights-measure-tick major' : 'flashlights-measure-tick'}
                    style={{ left: `${tick.leftPercent}%` }}
                  />
                ))}
              {measureTicks
                .filter((tick) => tick.isLabel)
                .map((tick) => {
                  const align = tick.leftPercent < 4 ? 'start' : tick.leftPercent > 96 ? 'end' : 'center';
                  return (
                    <div
                      key={`label-${tick.measure}`}
                      className="flashlights-measure-label"
                      style={{ left: `${tick.leftPercent}%` }}
                      data-align={align}
                    >
                      {tick.label}
                    </div>
                  );
                })}
            </div>
            {rehearsalMarkers.length > 0 && (
              <div className="flashlights-rehearsal-marker-row">
                {rehearsalMarkers.map((marker) => (
                  <div
                    key={marker.measure}
                    className={
                      marker.measure === activeRehearsalMeasure
                        ? 'flashlights-rehearsal-marker active'
                        : 'flashlights-rehearsal-marker'
                    }
                    style={{ left: `${marker.position}%` }}
                    title={`Rehearsal measure ${marker.measure}`}
                  >
                    <span className="flashlights-rehearsal-label">{marker.display}</span>
                    <span className="flashlights-rehearsal-tick" />
                  </div>
                ))}
              </div>
            )}
          </div>
          {selectionSummary && (
            <div className="flashlights-selection-summary" role="status">
              {selectionSummary}
            </div>
          )}
        </div>
        <div className="flashlights-timeline-controls" aria-hidden="true">
          <div className="flashlights-track-controls flashlights-track-controls--ghost">
            <button type="button" className="flashlights-track-button solo" tabIndex={-1}>Solo</button>
            <button type="button" className="flashlights-track-button mute" tabIndex={-1}>Muted</button>
          </div>
        </div>
      </div>

      {loadError && (
        <p className="flashlights-error-message" role="alert">
          {loadError}
        </p>
      )}

      <div className="flashlights-track-list" role="group" aria-label="Choir stems">
        {trackDefinitions.map((track, index) => {
          const isMuted = muteState[index];
          const isSolo = soloState[index];
          const isEffectivelySilent = soloActive ? !isSolo : isMuted;
          const rowClasses = ['flashlights-track-row'];
          if (isSolo) rowClasses.push('solo');
          if (isEffectivelySilent) rowClasses.push('muted');
          const accent = track.accent;

          return (
            <div
              key={track.id}
              className={rowClasses.join(' ')}
              data-accent={accent || undefined}
            >
              <div className="flashlights-track-label">
                <span className="flashlights-track-order">{String(index + 1).padStart(2, '0')}</span>
                <div className="flashlights-track-text">
                  {track.family && <span className="flashlights-track-family">{track.family}</span>}
                  <span className="flashlights-track-title">{track.shortLabel}</span>
                  <span className="flashlights-track-subtitle">{track.label}</span>
                </div>
              </div>
              <div
                className="flashlights-track-waveform-container"
                onPointerDown={handleWaveformPointerDown}
                onPointerMove={handleWaveformPointerMove}
                onPointerUp={handleWaveformPointerUp}
                onPointerCancel={handleWaveformPointerCancel}
              >
                <div
                  className="flashlights-waveform-selection"
                  style={selectionStyle ?? { display: 'none' }}
                  aria-hidden="true"
                />
                <FlashlightsWaveform
                  waveformId={track.waveformId}
                  className="flashlights-track-waveform"
                />
                <div
                  className="flashlights-waveform-playhead"
                  style={{ left: `${playheadPercent}%`, opacity: isLoaded ? 1 : 0 }}
                  aria-hidden="true"
                />
              </div>
              <div className="flashlights-track-controls">
                <button
                  type="button"
                  className={isSolo ? 'flashlights-track-button solo active' : 'flashlights-track-button solo'}
                  onClick={() => handleSoloToggle(index)}
                  aria-pressed={isSolo}
                  aria-label={`Solo ${track.label}`}
                  title={`Solo ${track.label}`}
                >
                  Solo
                </button>
                <button
                  type="button"
                  className={isMuted ? 'flashlights-track-button mute active' : 'flashlights-track-button mute'}
                  onClick={() => handleMuteToggle(index)}
                  aria-pressed={isMuted}
                  aria-label={`${isMuted ? 'Unmute' : 'Mute'} ${track.label}`}
                  title={`${isMuted ? 'Unmute' : 'Mute'} ${track.label}`}
                >
                  {isMuted ? 'Muted' : 'Mute'}
                </button>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

/**
 * Tabbed resource hub for the Flashlights in the Dark client.
 */
function FlashlightsInTheDarkTool({ onClose, activeTabKey, onTabChange, presentation = 'modal' }) {
  const isModal = presentation !== 'fullscreen';

  const [internalTabKey, setInternalTabKey] = useState(() =>
    typeof activeTabKey === 'string' ? activeTabKey : 'individual-parts'
  );
  const tabPanelRef = useRef(null);

  useEffect(() => {
    if (!isModal || typeof onClose !== 'function') {
      return undefined;
    }

    const handleKey = (e) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleKey);
    return () => window.removeEventListener('keydown', handleKey);
  }, [isModal, onClose]);

  const demoSrc = useMemo(() => resolveAssetUrl(FLASHLIGHTS_DEMO), []);
  const singerScoreSrc = useMemo(() => resolveAssetUrl(singerScorePdf), []);

  const tabs = useMemo(
    () => [
      {
        key: 'individual-parts',
        label: '13-Part Mixer',
        isNew: true,
        content: (
          <div className="flashlights-tab-panel flashlights-multitrack-panel">
            <FlashlightsMultiTrackMixer />
          </div>
        ),
      },
      {
        key: 'video',
        label: 'Video Demo',
        content: (
          <div className="flashlights-tab-panel flashlights-audio-panel">
            <div className="flashlights-coming-soon-banner">Video Demo Coming Soon…</div>
            <div className="flashlights-announcement" role="note">
              <strong>New:</strong> The <em>13-Part Mixer</em> tab (first in the toolbar) now hosts stem-by-stem waveforms and solo/mute controls for all thirteen Flashlights parts.
            </div>
            <div className="flashlights-audio-card">
              <div className="flashlights-audio-header">
                <div className="flashlights-audio-meta">
                  <h3 className="flashlights-audio-title">July 28, 2025 Virtual Choir Mockup</h3>
                  <p className="flashlights-audio-summary">
                    Draft mix for sectional prep & pitch reference only — balance cues and entrance timing.
                  </p>
                </div>
                <span className="flashlights-audio-duration">Draft mix • 3m 42s</span>
              </div>

              <div className="flashlights-waveform-wrapper">
                <FlashlightsWaveform waveformId="demo" />
              </div>

              <div className="flashlights-audio-controls">
                <audio className="flashlights-audio-player" controls src={demoSrc} preload="metadata">
                  Your browser does not support the audio element.
                </audio>
                <a className="flashlights-audio-download" href={demoSrc} download>
                  Download mockup audio
                </a>
              </div>

              <p className="flashlights-note flashlights-audio-note">
                Draft reference only — this virtual choir MIDI mockup is shared to illustrate cues, so
                please listen with caution and keep your expressive decisions flexible until live
                rehearsals.
              </p>
            </div>
          </div>
        ),
      },
      {
        key: 'install',
        label: 'Install iOS/Android App',
        content: (
          <div className="flashlights-tab-panel flashlights-install">
            <section className="flashlights-install-header flashlights-install-cta">
              <div className="flashlights-install-cta-text">
                <p className="flashlights-install-cta-kicker">You&apos;re in the right spot — this is the Flashlights install page.</p>
                <h2 className="flashlights-install-title">Download the Flashlights companion app</h2>
                <p>
                  Choir singers use this private rehearsal build to receive cues, pitch reference, and
                  lighting prompts. Follow the steps on your own device so you are show-ready before
                  call time.
                </p>
                <ul className="flashlights-install-prep">
                  <li>Use the phone or tablet you will carry on stage.</li>
                  <li>Connect to Wi-Fi and set aside about five minutes to finish the install.</li>
                  <li>Keep headphones nearby for the quick sound check at the end.</li>
                </ul>
              </div>
              <div className="flashlights-install-cta-actions" role="navigation" aria-label="Install quick links">
                <p className="flashlights-install-cta-note">Select your device to jump straight to the detailed steps.</p>
                <div className="flashlights-install-cta-buttons">
                  <a className="flashlights-cta-button" href="#flashlights-install-ios">
                    I&apos;m using iPhone or iPad
                  </a>
                  <a className="flashlights-cta-button secondary" href="#flashlights-install-android">
                    I&apos;m using Android
                  </a>
                </div>
                <ul className="flashlights-install-checklist">
                  <li>Have your choir login handy for the final sound check.</li>
                  <li>Charge to at least 50% and stay on Wi-Fi until the install completes.</li>
                  <li>Use the same device while you read and tap through each instruction below.</li>
                </ul>
              </div>
            </section>
            <div className="flashlights-install-grid">
              <section
                className="flashlights-card flashlights-install-card"
                id="flashlights-install-ios"
                aria-labelledby="flashlights-install-ios-title"
              >
                <header className="flashlights-install-card-header">
                  <span className="flashlights-platform-badge">iPhone &amp; iPad</span>
                  <h3 className="flashlights-card-title" id="flashlights-install-ios-title">
                    TestFlight rehearsal build
                  </h3>
                </header>
                <ol className="flashlights-steps flashlights-install-steps">
                  <li>On your iOS device, open the App Store and install Apple&apos;s TestFlight app.</li>
                  <li>
                    Return here on that same device and tap the button below. Safari will open the
                    Flashlights invite link.
                  </li>
                  <li>
                    In TestFlight, tap <strong>Accept</strong>, then <strong>Install</strong>. Stay on this
                    screen until the progress ring completes.
                  </li>
                  <li>
                    Tap <strong>Open</strong>. Allow Bluetooth, microphone, and notifications if iOS asks &mdash;
                    those power our cueing system.
                  </li>
                </ol>
                <a
                  className="flashlights-link-btn"
                  href="https://testflight.apple.com/join/9ASp48Jj"
                  target="_blank"
                  rel="noreferrer"
                >
                  Open TestFlight invitation
                </a>
                <p className="flashlights-note">
                  If you see &quot;This app is no longer available,&quot; delete any old Flashlights build in
                  TestFlight first, then accept the invite again.
                </p>
              </section>

              <section
                className="flashlights-card flashlights-install-card"
                id="flashlights-install-android"
                aria-labelledby="flashlights-install-android-title"
              >
                <header className="flashlights-install-card-header">
                  <span className="flashlights-platform-badge">Android</span>
                  <h3 className="flashlights-card-title" id="flashlights-install-android-title">
                    Google Play internal test
                  </h3>
                </header>
                <ol className="flashlights-steps flashlights-install-steps">
                  <li>
                    Make sure you are signed into Chrome with your own Google account—the one you use on
                    your Android device.
                  </li>
                  <li>
                    Tap the button below and choose <strong>Become a tester</strong>. Google Play will confirm you
                    are in the choir track.
                  </li>
                  <li>
                    Select <strong>Download it on Google Play</strong>, then tap <strong>Install</strong> (or
                    <strong>Update</strong> if the app is already there).
                  </li>
                  <li>
                    Open the app right away and approve audio, Bluetooth, and notification permissions so
                    we can run the rehearsal check-in.
                  </li>
                </ol>
                <a
                  className="flashlights-link-btn"
                  href="https://play.google.com/apps/internaltest/4701639500415117370"
                  target="_blank"
                  rel="noreferrer"
                >
                  Join the Android internal test
                </a>
                <p className="flashlights-note">
                  If the page says you need permission, confirm you are signed into the personal Google
                  account you want to use for Flashlights. Reach out to production if that address still
                  needs to be added.
                </p>
              </section>
            </div>

            <div className="flashlights-card flashlights-install-next" id="flashlights-install-after">
              <h3 className="flashlights-card-title">After installation</h3>
              <ul className="flashlights-install-followup">
                <li>
                  Log in with the rehearsal credentials from the latest choir notes. Message Jon if you
                  cannot locate them.
                </li>
                <li>Play the built-in sound check and confirm you hear the starter chime.</li>
                <li>
                  Charge your device fully and pack a Lightning or USB-C cable for backup power on show
                  day.
                </li>
              </ul>
            </div>
          </div>
        ),
      },
      {
        key: 'docs',
        label: 'Documentation',
        content: (
          <div className="flashlights-tab-panel">
            <div className="flashlights-score-panel">
              <div className="flashlights-score-intro">
                <p>
                  Open the 2023 singer score directly in the browser. Use the page controls to rehearse
                  each movement or grab an offline copy when you need to print parts.
                </p>
                <a
                  className="flashlights-score-download"
                  href={singerScoreSrc}
                  download="FlashlightsInTheDark_SingerScore_23.pdf"
                >
                  Download singer score PDF
                </a>
              </div>
              <div className="flashlights-score-viewer">
                <SimplePdfViewer file={singerScoreSrc} showControls height="68vh" />
              </div>
            </div>
            <p className="flashlights-instructions">
              Preview the control-room interface and the mobile performer view used during performances.
            </p>
            <div className="flashlights-media-grid">
              <figure className="flashlights-media-card flashlights-media-card--wide">
                <a href={img2} target="_blank" rel="noreferrer">
                  <img src={img2} alt="Flashlights MacOS conductor interface" loading="lazy" />
                </a>
                <figcaption>MacOS conductor console</figcaption>
              </figure>
              <figure className="flashlights-media-card flashlights-media-card--portrait">
                <a href={img3} target="_blank" rel="noreferrer">
                  <img src={img3} alt="Flashlights smartphone client" loading="lazy" />
                </a>
                <figcaption>Smartphone client UI</figcaption>
              </figure>
              <figure className="flashlights-media-card flashlights-media-card--wide">
                <a href={img4} target="_blank" rel="noreferrer">
                  <img src={img4} alt="Draft stage plot for Flashlights" loading="lazy" />
                </a>
                <figcaption>Draft stage plot (July 2025)</figcaption>
              </figure>
              <figure className="flashlights-media-card flashlights-media-card--wide">
                <a href={img5} target="_blank" rel="noreferrer">
                  <img src={img5} alt="Flashlights score arrangement demo" loading="lazy" />
                </a>
                <figcaption>Score arrangement demo</figcaption>
              </figure>
              <figure className="flashlights-media-card flashlights-media-card--portrait">
                <a href={img6} target="_blank" rel="noreferrer">
                  <img src={img6} alt="Shadow and Light poetry sheet for Flashlights" loading="lazy" />
                </a>
                <figcaption>Shadow &amp; Light twin poem</figcaption>
              </figure>
              <figure className="flashlights-media-card flashlights-media-card--panorama">
                <a href={img7} target="_blank" rel="noreferrer">
                  <img
                    src={img7}
                    alt="Flashlights light chorus parts and networking scheme"
                    loading="lazy"
                  />
                </a>
                <figcaption>Light chorus parts &amp; networking matrix</figcaption>
              </figure>
            </div>
          </div>
        ),
      },
      {
        key: 'privacy-policy',
        label: 'Privacy Policy',
        content: (
          <div className="flashlights-tab-panel">
            <FlashlightsPrivacyPolicy />
          </div>
        ),
      },
    ],
    [demoSrc, singerScoreSrc]
  );

  const tabKeys = useMemo(() => tabs.map((tab) => tab.key), [tabs]);
  const fallbackTabKey = useMemo(
    () => (tabKeys.includes('install') ? 'install' : tabKeys[0] ?? 'individual-parts'),
    [tabKeys]
  );

  useEffect(() => {
    if (typeof activeTabKey === 'string') {
      setInternalTabKey(tabKeys.includes(activeTabKey) ? activeTabKey : fallbackTabKey);
    }
  }, [activeTabKey, tabKeys, fallbackTabKey]);

  useEffect(() => {
    if (!tabKeys.includes(internalTabKey)) {
      setInternalTabKey(fallbackTabKey);
    }
  }, [internalTabKey, tabKeys, fallbackTabKey]);

  const selectedTab =
    tabs.find((tab) => tab.key === internalTabKey) ??
    tabs.find((tab) => tab.key === fallbackTabKey) ??
    tabs[0];
  const isInstallTabSelected = selectedTab?.key === 'install';
  const activeTabButtonId = selectedTab ? getTabButtonId(selectedTab.key) : undefined;

  useEffect(() => {
    if (typeof window === 'undefined') return undefined;
    if (isModal) return undefined;

    const panelNode = tabPanelRef.current;
    if (!panelNode) return undefined;

    const mobileQuery = window.matchMedia(`(max-width: ${AUTO_SCROLL_BREAKPOINT}px)`);
    if (!mobileQuery.matches) {
      return undefined;
    }

    const rect = panelNode.getBoundingClientRect();
    if (rect.top <= 120 && rect.top >= -48) {
      panelNode.focus({ preventScroll: true });
      return undefined;
    }

    const rafId = window.requestAnimationFrame(() => {
      panelNode.scrollIntoView({ behavior: 'smooth', block: 'start' });
      panelNode.focus({ preventScroll: true });
    });

    return () => window.cancelAnimationFrame(rafId);
  }, [selectedTab, isModal]);

  const handleTabChange = (key) => {
    if (key === internalTabKey) return;
    setInternalTabKey(key);
    if (onTabChange) onTabChange(key);
  };

  const handleTabKeyDown = useCallback(
    (event, index) => {
      const { key } = event;
      if (!tabKeys.length) return;
      if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(key)) return;

      event.preventDefault();

      let nextIndex = index;
      if (key === 'ArrowRight') {
        nextIndex = (index + 1) % tabKeys.length;
      } else if (key === 'ArrowLeft') {
        nextIndex = (index - 1 + tabKeys.length) % tabKeys.length;
      } else if (key === 'Home') {
        nextIndex = 0;
      } else if (key === 'End') {
        nextIndex = tabKeys.length - 1;
      }

      const nextKey = tabKeys[nextIndex];
      if (!nextKey) return;

      handleTabChange(nextKey);

      if (typeof document !== 'undefined') {
        const nextButton = document.getElementById(getTabButtonId(nextKey));
        if (nextButton) {
          nextButton.focus();
        }
      }
    },
    [handleTabChange, tabKeys]
  );

  const highlightCards = useMemo(
    () => [
      {
        key: 'individual-parts',
        badge: 'Focused Practice',
        title: '13-Part Mixer',
        description:
          'Solo, mute, or loop any stem with live rehearsal markers and instant waveform navigation.',
      },
      {
        key: 'install',
        badge: 'Devices ready',
        title: 'Install the Mobile App',
        description: 'Step-by-step setup for TestFlight on iOS and the Google Play internal test on Android.',
      },
      {
        key: 'docs',
        badge: 'Reference kit',
        title: 'Performance Documents',
        description: 'Preview the score, stage layout, and interface screenshots so you arrive rehearsal-ready.',
      },
      {
        key: 'video',
        badge: 'General Listening',
        title: 'Draft Demo Audio',
        description: 'Listen to the provisional mix while the full video cut renders—perfect for private practice.',
      },
    ],
    []
  );

  const containerClasses = ['flashlights-container'];
  containerClasses.push(
    isModal ? 'flashlights-container--modal' : 'flashlights-container--fullscreen'
  );
  if (isInstallTabSelected) {
    containerClasses.push('flashlights-container--install-active');
  }

  return (
    <div className={containerClasses.join(' ')}>
      {isModal && typeof onClose === 'function' && (
        <button className="flashlights-close" onClick={onClose} aria-label="Close panel">
          &times;
        </button>
      )}

      <header className="flashlights-header">
        <div className="flashlights-heading">
          <h1 className="flashlights-title">Flashlights in the Dark</h1>
          <p className="flashlights-subtitle">
            Everything singers need for the 2025&ndash;2026 Flashlights cohort&mdash;rehearsal audio, install
            guides, and production docs in one focused space.
          </p>
        </div>
        <div className="flashlights-chip-row" role="status" aria-live="polite">
          <span className="flashlights-chip">Multi-track mixer refreshed</span>
          <span className="flashlights-chip">Latest assets: Sept 2025 rehearsal drop</span>
        </div>
      </header>

      <section className="flashlights-highlights" aria-label="Resource shortcuts">
        {highlightCards.map((card) => {
          const isActiveCard = selectedTab?.key === card.key;
          return (
            <article
              key={card.key}
              className={
                isActiveCard
                  ? 'flashlights-highlight-card active'
                  : 'flashlights-highlight-card'
              }
            >
              <span className="flashlights-highlight-badge">{card.badge}</span>
              <h3>{card.title}</h3>
              <p>{card.description}</p>
              <button
                type="button"
                className="flashlights-highlight-action"
                onClick={() => handleTabChange(card.key)}
                aria-pressed={isActiveCard}
              >
                {isActiveCard ? 'Currently viewing' : 'Open this tab'}
              </button>
            </article>
          );
        })}
      </section>

      <div className="flashlights-tabs" role="tablist" aria-label="Flashlights resource tabs">
        {tabs.map((tab, index) => {
          const isActive = tab.key === selectedTab.key;
          const buttonClasses = ['flashlights-tab-button'];
          if (isActive) buttonClasses.push('active');
          if (tab.isNew) buttonClasses.push('new');
          return (
            <button
              key={tab.key}
              type="button"
              role="tab"
              aria-selected={isActive}
              className={buttonClasses.join(' ')}
              onClick={() => handleTabChange(tab.key)}
              onKeyDown={(event) => handleTabKeyDown(event, index)}
              id={getTabButtonId(tab.key)}
              aria-controls={FLASHLIGHTS_PANEL_ID}
              tabIndex={isActive ? 0 : -1}
            >
              <span className="flashlights-tab-label">{tab.label}</span>
              {tab.isNew && <span className="flashlights-tab-badge">New</span>}
            </button>
          );
        })}
      </div>

      <div
        className="flashlights-tab-content"
        role="tabpanel"
        id={FLASHLIGHTS_PANEL_ID}
        aria-labelledby={activeTabButtonId || undefined}
        ref={tabPanelRef}
        tabIndex={-1}
        data-active-tab={selectedTab?.key ?? ''}
      >
        {selectedTab?.content}
      </div>
    </div>
  );
}

export default FlashlightsInTheDarkTool;
