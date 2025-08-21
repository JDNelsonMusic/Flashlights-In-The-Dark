#!/usr/bin/env python3
import os, sys
import uvicorn

# Optional stub mode for heavy deps
STUB = os.environ.get("SIMPHONI_OPTIONAL_DEPS", "none").lower() == "stub"
if STUB:
    import types
    def _stub_whisper():
        m = types.ModuleType("whisper")
        class _DummyModel:
            def transcribe(self, *a, **k):
                raise RuntimeError("whisper not installed; install full requirements to enable transcription")
        def load_model(*a, **k): return _DummyModel()
        m.load_model = load_model
        sys.modules["whisper"] = m
    for name in ("whisper",):
        if name not in sys.modules:
            try: __import__(name)
            except Exception:
                if name == "whisper": _stub_whisper()

from simphoni_llm_server import app  # FastAPI instance

# Attach metrics router + middleware if present
try:
    from simphoni_llm_server.metrics_router import router as metrics_router, attach_metrics_middleware
    app.include_router(metrics_router)
    attach_metrics_middleware(app)
except Exception:
    pass

host = os.environ.get("SIMPHONI_HOST", "127.0.0.1")
port = int(os.environ.get("SIMPHONI_PORT", "8768"))
workers = int(os.environ.get("SIMPHONI_WORKERS", "1"))
log_level = os.environ.get("SIMPHONI_LOG_LEVEL", "info")

if __name__ == "__main__":
    uvicorn.run(app, host=host, port=port, workers=workers, log_level=log_level)
