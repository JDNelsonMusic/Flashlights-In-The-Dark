import { readdirSync, readFileSync, statSync } from 'node:fs';
import { extname, join, resolve } from 'node:path';

const outputDirectory = resolve(process.cwd(), process.argv[2] ?? 'dist-public');
const files = [];

const visit = (directory) => {
  for (const entry of readdirSync(directory)) {
    const path = join(directory, entry);
    if (statSync(path).isDirectory()) visit(path);
    else files.push(path);
  }
};

visit(outputDirectory);

const relativeNames = files.map((path) => path.slice(outputDirectory.length + 1));
const bannedNamePatterns = [
  /\.pdf$/i,
  /FlashlightsInTheDark_SingerScore/i,
  /2025_0728_FlashlightsInTheDark_24/i,
  /Sound_DemoMockup/i,
  /ScoreFormatDemo/i,
];
const bannedTextPatterns = [
  /pdfjs-dist/i,
  /SimplePdfViewer/i,
  /FlashlightsInTheDarkTool/i,
  /FlashlightsInTheDark_SingerScore/i,
  /2025_0728_FlashlightsInTheDark_24/i,
  /Sound_DemoMockup/i,
];

const unsafeNames = relativeNames.filter((name) => bannedNamePatterns.some((pattern) => pattern.test(name)));
if (unsafeNames.length > 0) {
  throw new Error(`Unsafe public build assets:\n${unsafeNames.join('\n')}`);
}

const textFiles = files.filter((path) => ['.js', '.css', '.html', '.json'].includes(extname(path)));
const unsafeText = [];
let embeddedStemCount = 0;
for (const path of textFiles) {
  const content = readFileSync(path, 'utf8');
  embeddedStemCount += content.match(/data:audio\/[A-Za-z0-9.+-]+;base64/g)?.length ?? 0;
  const match = bannedTextPatterns.find((pattern) => pattern.test(content));
  if (match) unsafeText.push(`${path.slice(outputDirectory.length + 1)} matched ${match}`);
}
if (unsafeText.length > 0) {
  throw new Error(`Unsafe public dependency references:\n${unsafeText.join('\n')}`);
}

const stemFiles = relativeNames.filter((name) => name.toLowerCase().endsWith('.mp3'));
const totalStemCount = stemFiles.length + embeddedStemCount;
if (totalStemCount !== 13) {
  throw new Error(`Expected exactly 13 approved mixer stems, found ${totalStemCount}`);
}

console.log(`Public build audit passed: ${relativeNames.length} files, 13 approved stems, no PDF or demo assets.`);
