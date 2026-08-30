import { lazy, Suspense, useEffect, useState } from 'react';
import FlashlightsHomePage from './landing';
import FlashlightsPracticePage from './practice';
import FlashlightsScorePage from './score';
import FlashlightsVideosPage from './videos';
import FlashlightsPrivacyPage from './privacy';
import FlashlightsDocumentationPage from './documentation';
import FlashlightsInstallPage from './install';
import './standalone.css';

const FlashlightsMixer = lazy(() => import('./mixer'));

const normalizedPath = (pathname) => pathname.replace(/\/+$/, '') || '/';

const routeForPath = (pathname) => {
  const path = normalizedPath(pathname);
  if (path.endsWith('/privacy-policy')) return { page: 'privacy' };
  if (path === '/install' || path.endsWith('/install')) return { page: 'install' };
  if (path.endsWith('/documentation')) return { page: 'documentation' };
  if (path.endsWith('/practice')) return { page: 'practice' };
  if (path.endsWith('/score')) return { page: 'score' };
  if (path.endsWith('/warm-ups')) return { page: 'videos', section: 'warm-ups' };
  if (path.endsWith('/presentation')) return { page: 'videos', section: 'presentation' };
  if (path.endsWith('/videos')) return { page: 'videos' };
  if (path.endsWith('/mixer')) return { page: 'mixer' };
  return { page: 'home' };
};

function LoadingSurface() {
  return (
    <main className="flashlights-public-loading" aria-live="polite">
      <p>Loading rehearsal tools…</p>
    </main>
  );
}

export default function StandaloneApp() {
  const [route, setRoute] = useState(() => routeForPath(window.location.pathname));

  useEffect(() => {
    const updateRoute = () => setRoute(routeForPath(window.location.pathname));
    window.addEventListener('popstate', updateRoute);
    return () => window.removeEventListener('popstate', updateRoute);
  }, []);

  useEffect(() => {
    if (!route.section) return;
    document.getElementById(route.section)?.scrollIntoView({ block: 'start' });
  }, [route]);

  if (route.page === 'practice') return <FlashlightsPracticePage />;
  if (route.page === 'score') return <FlashlightsScorePage />;
  if (route.page === 'videos') return <FlashlightsVideosPage />;
  if (route.page === 'privacy') return <FlashlightsPrivacyPage />;
  if (route.page === 'documentation') return <FlashlightsDocumentationPage />;
  if (route.page === 'install') return <FlashlightsInstallPage />;
  if (route.page === 'mixer') {
    return (
      <main className="flashlights-public-app">
        <Suspense fallback={<LoadingSurface />}>
          <FlashlightsMixer />
        </Suspense>
      </main>
    );
  }
  return <FlashlightsHomePage />;
}
