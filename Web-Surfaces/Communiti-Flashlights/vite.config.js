import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { resolve } from 'node:path';

const isLibraryBuild = process.env.BUILD_TARGET === 'library';

export default defineConfig({
  plugins: [react()],
  build: isLibraryBuild
    ? {
        emptyOutDir: true,
        lib: {
          entry: {
            index: resolve(import.meta.dirname, 'src/index.jsx'),
            landing: resolve(import.meta.dirname, 'src/landing.jsx'),
            score: resolve(import.meta.dirname, 'src/score.jsx'),
            practice: resolve(import.meta.dirname, 'src/practice.jsx'),
            videos: resolve(import.meta.dirname, 'src/videos.jsx'),
            mixer: resolve(import.meta.dirname, 'src/mixer.jsx'),
            privacy: resolve(import.meta.dirname, 'src/privacy.jsx'),
            resources: resolve(import.meta.dirname, 'src/resources.js'),
          },
          formats: ['es'],
          fileName: (_format, entryName) => `${entryName}.js`,
          cssFileName: 'style',
        },
        rollupOptions: {
          external: ['react', 'react-dom'],
        },
      }
    : {
        emptyOutDir: true,
        outDir: 'dist-site',
      },
  test: {
    environment: 'jsdom',
  },
});
