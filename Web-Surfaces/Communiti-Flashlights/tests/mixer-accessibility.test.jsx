import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import FlashlightsMixer from '../src/mixer';
import {
  createMixerTransportKeyHandler,
  isMixerShortcutInteractiveTarget,
} from '../src/components/FlashlightsMultiTrackMixer';

const mixerCss = readFileSync(
  resolve(process.cwd(), 'src/components/FlashlightsMultiTrackMixer.css'),
  'utf8'
);

const createInteractiveTarget = (descriptor) => {
  const [kind, value] = descriptor.split(':');
  if (kind === 'tag') return document.createElement(value);
  const element = document.createElement('div');
  if (kind === 'role') element.setAttribute('role', value);
  if (kind === 'attribute') element.setAttribute(value, 'true');
  return element;
};

const interactiveTargets = [
  'tag:button',
  'tag:a',
  'tag:input',
  'tag:textarea',
  'tag:select',
  'tag:summary',
  'attribute:contenteditable',
  'role:button',
  'role:link',
  'role:checkbox',
  'role:radio',
  'role:switch',
  'role:slider',
  'role:spinbutton',
  'role:menuitem',
];

const makeSpaceEvent = (target, overrides = {}) => ({
  code: 'Space',
  key: ' ',
  target,
  defaultPrevented: false,
  preventDefault: vi.fn(),
  ...overrides,
});

describe('mixer Space shortcut', () => {
  it.each(interactiveTargets)('ignores Space from %s and its descendants', (descriptor) => {
    const interactive = createInteractiveTarget(descriptor);
    const nestedTarget = document.createElement('span');
    interactive.append(nestedTarget);
    const startPlayback = vi.fn();
    const stopPlayback = vi.fn();
    const handler = createMixerTransportKeyHandler({
      isPlayingRef: { current: false },
      startPlayback,
      stopPlayback,
    });

    expect(isMixerShortcutInteractiveTarget(nestedTarget)).toBe(true);
    const event = makeSpaceEvent(nestedTarget);
    handler(event);

    expect(event.preventDefault).not.toHaveBeenCalled();
    expect(startPlayback).not.toHaveBeenCalled();
    expect(stopPlayback).not.toHaveBeenCalled();
  });

  it('preserves the global Space shortcut on non-interactive page content', () => {
    const startPlayback = vi.fn();
    const stopPlayback = vi.fn();
    const isPlayingRef = { current: false };
    const handler = createMixerTransportKeyHandler({ isPlayingRef, startPlayback, stopPlayback });
    const target = document.createElement('div');

    const playEvent = makeSpaceEvent(target);
    handler(playEvent);
    expect(playEvent.preventDefault).toHaveBeenCalledOnce();
    expect(startPlayback).toHaveBeenCalledOnce();

    isPlayingRef.current = true;
    const stopEvent = makeSpaceEvent(target);
    handler(stopEvent);
    expect(stopEvent.preventDefault).toHaveBeenCalledOnce();
    expect(stopPlayback).toHaveBeenCalledOnce();
  });

  it('does not handle a non-Space or already-prevented event', () => {
    const startPlayback = vi.fn();
    const stopPlayback = vi.fn();
    const handler = createMixerTransportKeyHandler({
      isPlayingRef: { current: false },
      startPlayback,
      stopPlayback,
    });
    const target = document.createElement('div');

    handler(makeSpaceEvent(target, { code: 'Enter', key: 'Enter' }));
    handler(makeSpaceEvent(target, { defaultPrevented: true }));
    expect(startPlayback).not.toHaveBeenCalled();
    expect(stopPlayback).not.toHaveBeenCalled();
  });
});

describe('mixer announcements', () => {
  it('keeps elapsed time outside one narrow discrete-status live region', () => {
    const host = document.createElement('div');
    host.innerHTML = renderToStaticMarkup(<FlashlightsMixer />);
    const mixer = host.querySelector('.flashlights-multitrack');
    const elapsedTime = host.querySelector('.flashlights-transport-time');
    const liveRegions = mixer.querySelectorAll('[aria-live]');

    expect(mixer.hasAttribute('aria-live')).toBe(false);
    expect(liveRegions).toHaveLength(1);
    expect(liveRegions[0].classList.contains('flashlights-mixer-live-status')).toBe(true);
    expect(liveRegions[0].getAttribute('role')).toBe('status');
    expect(elapsedTime.closest('[aria-live]')).toBeNull();
  });
});

describe('mixer text sizing', () => {
  it('does not declare meaningful mixer text below 18px at a 16px rem root', () => {
    const undersizedValues = [...mixerCss.matchAll(/font-size:\s*([\d.]+)(rem|px)/g)]
      .filter(([, value, unit]) => (unit === 'rem' ? Number(value) * 16 : Number(value)) < 18)
      .map((match) => match[0]);

    expect(undersizedValues).toEqual([]);
  });
});
