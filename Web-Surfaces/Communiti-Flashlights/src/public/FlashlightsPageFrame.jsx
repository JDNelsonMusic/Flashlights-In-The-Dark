import React from 'react';
import './public.css';

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
  ['score', 'score', 'Score'],
  ['practice', 'practice', 'Practice'],
  ['videos', 'videos', 'Videos'],
  ['mixer', 'mixer', 'Mixer'],
];

export function FlashlightsPageFrame({ basePath = '/flashlights', currentPage, children }) {
  const normalizedBasePath = normalizeBasePath(basePath);

  return (
    <div className="flashlights-singer">
      <a className="flashlights-singer__skip-link" href="#flashlights-main">
        Skip to main content
      </a>
      <header className="flashlights-singer__header">
        <div className="flashlights-singer__header-inner">
          <a className="flashlights-singer__wordmark" href={normalizedBasePath}>
            <span aria-hidden="true" className="flashlights-singer__wordmark-light">●</span>
            <span>Flashlights in the Dark</span>
          </a>
          <nav aria-label="Flashlights resources">
            <ul className="flashlights-singer__nav-list">
              {NAV_ITEMS.map(([key, suffix, label]) => (
                <li key={key}>
                  <a
                    aria-current={currentPage === key ? 'page' : undefined}
                    href={resourcePath(normalizedBasePath, suffix)}
                  >
                    {label}
                  </a>
                </li>
              ))}
            </ul>
          </nav>
        </div>
      </header>
      <main id="flashlights-main" tabIndex="-1" className="flashlights-singer__main">
        {children}
      </main>
      <footer className="flashlights-singer__footer">
        <p>Public singer resources for Flashlights in the Dark.</p>
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
