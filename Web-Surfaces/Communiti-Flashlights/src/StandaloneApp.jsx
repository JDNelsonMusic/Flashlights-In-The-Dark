import { useEffect, useState } from 'react';
import { FlashlightsInTheDarkTool } from './index';
import './standalone.css';

const tabForPath = (pathname) => {
  if (pathname.endsWith('/privacy-policy')) return 'privacy-policy';
  if (pathname === '/install' || pathname.endsWith('/install')) return 'install';
  if (pathname.endsWith('/documentation')) return 'docs';
  return undefined;
};

const pathForTab = (tab) => {
  if (tab === 'privacy-policy') return '/privacy-policy';
  if (tab === 'install') return '/install';
  if (tab === 'docs') return '/documentation';
  return '/';
};

export default function StandaloneApp() {
  const [activeTabKey, setActiveTabKey] = useState(() => tabForPath(window.location.pathname));

  useEffect(() => {
    const updateTab = () => setActiveTabKey(tabForPath(window.location.pathname));
    window.addEventListener('popstate', updateTab);
    return () => window.removeEventListener('popstate', updateTab);
  }, []);

  const handleTabChange = (tab) => {
    const nextPath = pathForTab(tab);
    if (nextPath !== window.location.pathname) {
      window.history.pushState({}, '', nextPath);
    }
    setActiveTabKey(tab);
  };

  return (
    <main className="flashlights-public-app">
      <FlashlightsInTheDarkTool
        presentation="fullscreen"
        activeTabKey={activeTabKey}
        onTabChange={handleTabChange}
      />
    </main>
  );
}
