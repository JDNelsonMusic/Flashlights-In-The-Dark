import { describe, expect, it } from 'vitest';
import { FlashlightsInTheDarkTool, FlashlightsPrivacyPolicy } from '../src/index';

describe('public package API', () => {
  it('exports the Flashlights surface and privacy policy', () => {
    expect(FlashlightsInTheDarkTool).toBeTypeOf('function');
    expect(FlashlightsPrivacyPolicy).toBeTypeOf('function');
  });
});
