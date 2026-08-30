import { describe, expect, it } from 'vitest';
import { FlashlightsInTheDarkTool, FlashlightsPrivacyPolicy } from '../src/index';
import FlashlightsHomePage, { FlashlightsHomePage as NamedHomePage } from '../src/landing';
import FlashlightsScorePage, { FlashlightsScorePage as NamedScorePage } from '../src/score';
import FlashlightsPracticePage, { FlashlightsPracticePage as NamedPracticePage } from '../src/practice';
import FlashlightsVideosPage, { FlashlightsVideosPage as NamedVideosPage } from '../src/videos';
import FlashlightsMixer, { FlashlightsMixer as NamedMixer } from '../src/mixer';
import FlashlightsDocumentationPage, { FlashlightsDocumentationPage as NamedDocumentationPage } from '../src/documentation';
import FlashlightsInstallPage, { FlashlightsInstallPage as NamedInstallPage } from '../src/install';
import PublicPrivacyPolicy, {
  FlashlightsPrivacyPage as NamedPrivacyPage,
  FlashlightsPrivacyPolicy as NamedPrivacyPolicy,
} from '../src/privacy';
import { flashlightsResourceManifest } from '../src/resources';

describe('public package API', () => {
  it('exports the Flashlights surface and privacy policy', () => {
    expect(FlashlightsInTheDarkTool).toBeTypeOf('function');
    expect(FlashlightsPrivacyPolicy).toBeTypeOf('function');
  });

  it('provides stable default and named lightweight entry points', () => {
    expect(FlashlightsHomePage).toBe(NamedHomePage);
    expect(FlashlightsScorePage).toBe(NamedScorePage);
    expect(FlashlightsPracticePage).toBe(NamedPracticePage);
    expect(FlashlightsVideosPage).toBe(NamedVideosPage);
    expect(FlashlightsMixer).toBe(NamedMixer);
    expect(FlashlightsDocumentationPage).toBe(NamedDocumentationPage);
    expect(FlashlightsInstallPage).toBe(NamedInstallPage);
    expect(PublicPrivacyPolicy).toBe(NamedPrivacyPolicy);
    expect(PublicPrivacyPolicy).toBe(NamedPrivacyPage);
    expect(FlashlightsMixer).not.toBe(FlashlightsInTheDarkTool);
    expect(PublicPrivacyPolicy).not.toBe(FlashlightsPrivacyPolicy);
    expect(flashlightsResourceManifest.schemaVersion).toBe(1);
  });
});
