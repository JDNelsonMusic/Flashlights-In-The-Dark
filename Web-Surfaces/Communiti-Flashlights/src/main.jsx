import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import StandaloneApp from './StandaloneApp';

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <StandaloneApp />
  </StrictMode>
);
