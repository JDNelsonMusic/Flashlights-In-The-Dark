import React, { useEffect, useMemo, useRef, useState } from 'react';
import type { ChangeEvent } from 'react';
import type {
  PDFDocumentLoadingTask,
  PDFDocumentProxy,
  RenderTask,
} from 'pdfjs-dist/types/src/display/api';

interface SimplePdfViewerProps {
  file: string;
  showControls?: boolean;
  height?: string | number;
}

const clamp = (value: number, min: number, max: number) => Math.min(Math.max(value, min), max);

async function loadPdfjs() {
  const pdfjs = await import('pdfjs-dist/build/pdf');
  if (!pdfjs.GlobalWorkerOptions.workerSrc) {
    const worker = await import('pdfjs-dist/build/pdf.worker?url');
    pdfjs.GlobalWorkerOptions.workerSrc = worker.default;
  }
  return pdfjs;
}

export default function SimplePdfViewer({
  file,
  showControls = false,
  height = '100%',
}: SimplePdfViewerProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const pdfRef = useRef<PDFDocumentProxy | null>(null);

  const [pdfDoc, setPdfDoc] = useState<PDFDocumentProxy | null>(null);
  const [pageCount, setPageCount] = useState(0);
  const [page, setPage] = useState(1);
  const [viewportWidth, setViewportWidth] = useState(0);
  const [isDocumentLoading, setIsDocumentLoading] = useState(true);
  const [isRendering, setIsRendering] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const effectiveHeight = useMemo(
    () => (typeof height === 'number' ? `${height}px` : height),
    [height]
  );

  useEffect(() => {
    let isMounted = true;
    let loadingTask: PDFDocumentLoadingTask | null = null;

    const loadDocument = async () => {
      setIsDocumentLoading(true);
      setError(null);

      if (pdfRef.current) {
        try {
          pdfRef.current.destroy();
        } catch (err) {
          console.warn('Error while disposing previous PDF document', err);
        }
        pdfRef.current = null;
      }
      setPdfDoc(null);
      setPageCount(0);

      try {
        const pdfjs = await loadPdfjs();
        loadingTask = pdfjs.getDocument(file);
        const doc = await loadingTask.promise;
        if (!isMounted) {
          doc.destroy();
          return;
        }

        pdfRef.current = doc;
        setPdfDoc(doc);
        setPageCount(doc.numPages ?? 0);
        setPage((prev) => clamp(prev, 1, doc.numPages || 1));
      } catch (err) {
        if (!isMounted) return;
        console.error('Failed to load PDF document', err);
        setError(err instanceof Error ? err.message : 'Failed to load PDF');
      } finally {
        if (isMounted) {
          setIsDocumentLoading(false);
        }
      }
    };

    loadDocument();

    return () => {
      isMounted = false;
      if (loadingTask) {
        loadingTask.destroy();
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [file]);

  useEffect(() => {
    if (typeof window === 'undefined') return;
    const node = containerRef.current;
    if (!node) return;

    const updateWidth = () => {
      setViewportWidth(node.clientWidth);
    };
    updateWidth();

    if ('ResizeObserver' in window) {
      const observer = new ResizeObserver(updateWidth);
      observer.observe(node);
      return () => observer.disconnect();
    }

    const resizeListener = () => updateWidth();
    window.addEventListener('resize', resizeListener);
    return () => window.removeEventListener('resize', resizeListener);
  }, []);

  useEffect(() => {
    if (!pageCount) {
      setPage(1);
    } else {
      setPage((prev) => clamp(prev, 1, pageCount));
    }
  }, [pageCount]);

  useEffect(() => {
    const doc = pdfDoc;
    if (!doc) return;

    let cancelled = false;
    let renderTask: RenderTask | null = null;

    const renderPage = async () => {
      const canvas = canvasRef.current;
      if (!canvas) return;

      try {
        setIsRendering(true);
        const pdfPage = await doc.getPage(page);
        if (cancelled) return;

        const viewport = pdfPage.getViewport({ scale: 1 });
        const baseWidth = viewportWidth || viewport.width;
        const scale = baseWidth / viewport.width;
        const devicePixelRatio =
          typeof window !== 'undefined' ? window.devicePixelRatio || 1 : 1;
        const finalViewport = pdfPage.getViewport({ scale: scale * devicePixelRatio });

        const context = canvas.getContext('2d');
        if (!context) {
          setError('Unable to render PDF page.');
          setIsRendering(false);
          return;
        }

        canvas.width = finalViewport.width;
        canvas.height = finalViewport.height;
        canvas.style.width = `${finalViewport.width / devicePixelRatio}px`;
        canvas.style.height = `${finalViewport.height / devicePixelRatio}px`;

        context.setTransform(1, 0, 0, 1, 0, 0);

        renderTask = pdfPage.render({ canvasContext: context, viewport: finalViewport });
        await renderTask.promise;
        if (cancelled) return;
        setIsRendering(false);
      } catch (err) {
        if (cancelled) return;
        console.error('Failed to render PDF page', err);
        setError(err instanceof Error ? err.message : 'Failed to render PDF');
        setIsRendering(false);
      }
    };

    renderPage();

    return () => {
      cancelled = true;
      if (renderTask) {
        renderTask.cancel();
      }
    };
  }, [pdfDoc, page, viewportWidth]);

  const canGoPrev = page > 1;
  const canGoNext = pageCount > 0 && page < pageCount;
  const showToolbar = showControls && pageCount > 0;
  const showSlider = pageCount > 1;
  const isBusy = isDocumentLoading || isRendering;

  const handlePrev = () => setPage((prev) => clamp(prev - 1, 1, pageCount || 1));
  const handleNext = () => setPage((prev) => clamp(prev + 1, 1, pageCount || 1));
  const handleSliderChange = (event: ChangeEvent<HTMLInputElement>) => {
    const nextPage = Number(event.target.value);
    setPage(clamp(nextPage, 1, pageCount || 1));
  };

  return (
    <div className="simple-pdf-viewer" ref={containerRef}>
      {showToolbar && (
        <div className="pdf-controls" role="toolbar" aria-label="PDF page controls">
          <button type="button" onClick={handlePrev} disabled={!canGoPrev}>
            Prev
          </button>
          {showSlider && (
            <input
              className="pdf-slider"
              type="range"
              min={1}
              max={pageCount}
              step={1}
              value={page}
              onChange={handleSliderChange}
              aria-label="Jump to page"
            />
          )}
          <span className="pdf-page">
            Page {page}
            {pageCount ? ` / ${pageCount}` : ''}
          </span>
          <button type="button" onClick={handleNext} disabled={!canGoNext}>
            Next
          </button>
        </div>
      )}

      <div
        className="simple-pdf-viewer__viewport"
        style={effectiveHeight ? { minHeight: effectiveHeight } : undefined}
      >
        <canvas
          ref={canvasRef}
          className="simple-pdf-viewer__canvas"
          role="img"
          aria-label={
            pageCount ? `Score page ${page} of ${pageCount}` : `Score page ${page}`
          }
        />
        {isBusy && !error && (
          <div className="simple-pdf-viewer__loader" role="status" aria-live="polite">
            {isDocumentLoading ? 'Loading score…' : 'Rendering page…'}
          </div>
        )}
        {error && !isBusy && (
          <div className="simple-pdf-viewer__error" role="alert">
            {error}
          </div>
        )}
      </div>
    </div>
  );
}
