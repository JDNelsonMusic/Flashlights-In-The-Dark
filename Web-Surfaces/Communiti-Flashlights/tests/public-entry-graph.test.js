import { existsSync, readFileSync } from 'node:fs';
import { dirname, extname, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const sourceRoot = resolve(process.cwd(), 'src');
const entrypoints = [
  'landing.jsx',
  'score.jsx',
  'practice.jsx',
  'videos.jsx',
  'mixer.jsx',
  'documentation.jsx',
  'install.jsx',
  'privacy.jsx',
  'resources.js',
];
const sourceExtensions = ['', '.js', '.jsx', '.ts', '.tsx', '.json', '.css'];

const resolveImport = (fromPath, specifier) => {
  if (!specifier.startsWith('.')) return null;
  const base = resolve(dirname(fromPath), specifier);
  return sourceExtensions.map((extension) => `${base}${extension}`).find(existsSync) ?? null;
};

const collectStaticGraph = (entries) => {
  const visited = new Set();
  const pending = entries.map((entry) => resolve(sourceRoot, entry));
  while (pending.length > 0) {
    const path = pending.pop();
    if (visited.has(path)) continue;
    visited.add(path);
    if (!['.js', '.jsx', '.ts', '.tsx', '.css'].includes(extname(path))) continue;
    const source = readFileSync(path, 'utf8');
    const patterns = [
      /(?:import|export)\s+[\s\S]*?\sfrom\s*['"]([^'"]+)['"]/g,
      /import\s*['"]([^'"]+)['"]/g,
    ];
    for (const pattern of patterns) {
      for (const match of source.matchAll(pattern)) {
        const dependency = resolveImport(path, match[1]);
        if (dependency) pending.push(dependency);
      }
    }
  }
  return [...visited];
};

describe('public entry dependency graph', () => {
  it('does not import the legacy hub, PDF viewer, real score, or unapproved demo assets', () => {
    const graph = collectStaticGraph(entrypoints);
    expect(graph.some((path) => path.endsWith('/components/FlashlightsInTheDarkTool.jsx'))).toBe(false);
    expect(graph.some((path) => path.endsWith('/components/SimplePdfViewer.tsx'))).toBe(false);
    expect(graph.some((path) => /SingerScore|ScoreFormatDemo|Sound_DemoMockup/.test(path))).toBe(false);
    expect(graph.some((path) => path.endsWith('.pdf'))).toBe(false);
    expect(graph.some((path) => path.endsWith('/components/FlashlightsMultiTrackMixer.jsx'))).toBe(true);
  });

  it('keeps the package root compatibility export separate from the public mixer entry', () => {
    const rootEntry = readFileSync(resolve(sourceRoot, 'index.jsx'), 'utf8');
    const mixerEntry = readFileSync(resolve(sourceRoot, 'mixer.jsx'), 'utf8');
    expect(rootEntry).toContain("./components/FlashlightsInTheDarkTool");
    expect(mixerEntry).toContain("./public/FlashlightsMixerPage");
    expect(mixerEntry).not.toContain('FlashlightsInTheDarkTool');
  });
});
