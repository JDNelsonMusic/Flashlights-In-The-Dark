import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

const isLibraryBuild = process.env.BUILD_TARGET === 'library';

export default defineConfig({
  plugins: [react()],
  build: isLibraryBuild
    ? {
        emptyOutDir: true,
        lib: {
          entry: 'src/index.jsx',
          formats: ['es'],
          fileName: 'index',
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
