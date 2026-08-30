import React, { useEffect, useState } from 'react';
import './public.css';

export const FLASHLIGHTS_THEME_STORAGE_KEY = 'flashlights-resource-theme';

export const resolveInitialTheme = (storage) => {
  try {
    return storage?.getItem(FLASHLIGHTS_THEME_STORAGE_KEY) === 'dark' ? 'dark' : 'light';
  } catch {
    return 'light';
  }
};

export const normalizeBasePath = (basePath = '/flashlights') => {
  const withLeadingSlash = basePath.startsWith('/') ? basePath : `/${basePath}`;
  return withLeadingSlash.replace(/\/+$/, '') || '/flashlights';
};

export const resourcePath = (basePath, suffix = '') => {
  const base = normalizeBasePath(basePath);
  return suffix ? `${base}/${suffix.replace(/^\/+/, '')}` : base;
};

const NAV_ITEMS = [
  ['home', '', 'Home'],
  ['resources', 'documentation', 'Resources'],
  ['practice', 'practice', 'Practice'],
  ['install', 'install', 'Get the app'],
  ['mixer', 'mixer', 'Mixer'],
];

function ResourceNavigation({ basePath, currentPage, className, label }) {
  return (
    <nav className={className} aria-label={label}>
      <ul className="flashlights-singer__nav-list">
        {NAV_ITEMS.map(([key, suffix, itemLabel]) => (
          <li key={key}>
            <a
              aria-current={currentPage === key ? 'page' : undefined}
              href={resourcePath(basePath, suffix)}
            >
              {itemLabel}
            </a>
          </li>
        ))}
      </ul>
    </nav>
  );
}

export function FlashlightsPageFrame({ basePath = '/flashlights', currentPage, children }) {
  const normalizedBasePath = normalizeBasePath(basePath);
  const [theme, setTheme] = useState(() => resolveInitialTheme(
    typeof window === 'undefined' ? null : window.localStorage
  ));

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    document.documentElement.style.colorScheme = theme;
    document.querySelector('meta[name="theme-color"]')?.setAttribute(
      'content',
      theme === 'dark' ? '#141216' : '#fffdf8'
    );
  }, [theme]);

  const toggleTheme = () => {
    const nextTheme = theme === 'dark' ? 'light' : 'dark';
    setTheme(nextTheme);
    try {
      window.localStorage.setItem(FLASHLIGHTS_THEME_STORAGE_KEY, nextTheme);
    } catch {
      // The visual toggle still works when storage is unavailable.
    }
  };

  return (
    <div className="flashlights-singer" data-theme={theme}>
      <a className="flashlights-singer__skip-link" href="#flashlights-main">
        Skip to main content
      </a>
      <header className="flashlights-singer__header">
        <div className="flashlights-singer__header-inner">
          <a className="flashlights-singer__wordmark" href={normalizedBasePath}>
            <span aria-hidden="true" className="flashlights-singer__wordmark-light">✦</span>
            <span>Flashlights in the Dark</span>
          </a>
          <ResourceNavigation
            basePath={normalizedBasePath}
            currentPage={currentPage}
            className="flashlights-singer__desktop-nav"
            label="Flashlights resources"
          />
          <details className="flashlights-singer__mobile-menu">
            <summary>Menu</summary>
            <ResourceNavigation
              basePath={normalizedBasePath}
              currentPage={currentPage}
              label="Flashlights resources in menu"
            />
          </details>
          <button
            type="button"
            className="flashlights-singer__theme-toggle"
            aria-pressed={theme === 'dark'}
            onClick={toggleTheme}
          >
            <span aria-hidden="true">{theme === 'dark' ? '☀' : '☾'}</span>
            <span>{theme === 'dark' ? 'Light mode' : 'Dark mode'}</span>
          </button>
        </div>
      </header>
      <main id="flashlights-main" tabIndex="-1" className="flashlights-singer__main">
        {children}
      </main>
      <footer className="flashlights-singer__footer">
        <div>
          <p><strong>Permanent singer resource address</strong></p>
          <p><a href="https://keex.ai/flashlights">keex.ai/flashlights</a></p>
        </div>
        <nav aria-label="Flashlights help and policies">
          <a href={resourcePath(normalizedBasePath, 'documentation')}>All resources</a>
          <a href={resourcePath(normalizedBasePath, 'install')}>Install the app</a>
          <a href={resourcePath(normalizedBasePath, 'privacy-policy')}>Privacy</a>
        </nav>
        <p className="flashlights-singer__trademarks">
          Apple, iPhone, iPad, and TestFlight are trademarks of Apple Inc. Android and Google Play
          are trademarks of Google LLC. The Android robot is reproduced or modified from work
          created and shared by Google and used according to terms described in the{' '}
          <a href="https://creativecommons.org/licenses/by/3.0/">Creative Commons 3.0 Attribution License</a>.
        </p>
      </footer>
    </div>
  );
}

export function ResourceStatus({ children = 'Coming soon' }) {
  return <p className="flashlights-singer__status">{children}</p>;
}

export function BookletMockup() {
  return (
    <figure className="flashlights-booklet">
      <div
        className="flashlights-booklet__sheets"
        role="img"
        aria-label="12-page booklet · three 11×17 sheets · folds to 8.5×11"
      >
        <span className="flashlights-booklet__sheet flashlights-booklet__sheet--back" aria-hidden="true" />
        <span className="flashlights-booklet__sheet flashlights-booklet__sheet--middle" aria-hidden="true" />
        <span className="flashlights-booklet__sheet flashlights-booklet__sheet--front" aria-hidden="true">
          <span>Flashlights</span>
          <span>in the Dark</span>
          <small>Formal score</small>
        </span>
      </div>
      <figcaption>
        <strong>12-page booklet · three 11×17 sheets · folds to 8.5×11</strong>
      </figcaption>
    </figure>
  );
}
