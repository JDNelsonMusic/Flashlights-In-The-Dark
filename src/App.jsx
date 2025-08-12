import { Routes, Route } from 'react-router-dom';
import SimpleChat from './routes/simple-chat';
import SimplifiRoute from '@/routes/simplifi';
import Simphoni1vRoute from '@/routes/simphoni-1v';

/* Two routes for SimpleChat */
// - /simple-chat         => Pro-mode (SimpleChat)
// - /simplifi            => SimplifiRoute
// - /simphoni-1v         => Simphoni1vRoute

export default function App() {
  return (
    <Routes>
      <Route path="/simple-chat" element={<SimpleChat />} />
      <Route path="/simplifi" element={<SimplifiRoute />} />
      <Route path="/simphoni-1v" element={<Simphoni1vRoute />} />
    </Routes>
  );
}
