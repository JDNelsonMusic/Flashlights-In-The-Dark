from fastapi import APIRouter, FastAPI, Request
from pydantic import BaseModel
import time, os, subprocess

router = APIRouter()

# --- server counters ---
_BOOT_TIME = time.time()
_requests = 0
_active_tasks = 0
_compute_enabled = False

# --- optional deps ---
try:
    import psutil  # CPU/mem/swap
except Exception:
    psutil = None

try:
    import torch
    _has_mps = bool(getattr(torch.backends, "mps", None)) and torch.backends.mps.is_available()
except Exception:
    torch = None
    _has_mps = False

def attach_metrics_middleware(app: FastAPI) -> None:
    """
    Adds an HTTP middleware to count in-flight requests and total requests.
    """
    @app.middleware("http")
    async def _counting_mw(request: Request, call_next):
        global _requests, _active_tasks
        _active_tasks += 1
        try:
            response = await call_next(request)
            return response
        finally:
            _active_tasks -= 1
            _requests += 1

# --- helpers ---
def _sysctl_bytes(key: str) -> int | None:
    try:
        out = subprocess.check_output(["/usr/sbin/sysctl", "-n", key], text=True).strip()
        return int(out)
    except Exception:
        return None

def _mps_mem_used_bytes() -> int | None:
    """
    Best-effort report of MPS memory in bytes.
    Different torch versions expose different functions; try a few.
    """
    if not (_has_mps and torch is not None):
        return None
    try:
        for attr in ("current_allocated_memory", "driver_allocated_memory"):
            f = getattr(torch.mps, attr, None)
            if callable(f):
                try:
                    val = int(f())
                    if val >= 0:
                        return val
                except Exception:
                    pass
    except Exception:
        pass
    return None

# --- API models ---
class ComputeToggle(BaseModel):
    enabled: bool

# --- routes ---
@router.post("/admin/compute/enable")
def admin_compute_enable(t: ComputeToggle):
    """
    Toggle local compute contribution (best-effort flag surfaced in /metrics).
    """
    global _compute_enabled
    _compute_enabled = bool(t.enabled)
    return {"ok": True, "enabled": _compute_enabled}

@router.get("/metrics")
def metrics():
    """
    Shape matches the MMI Swift client:
    {
      "system": {
        "cpu_percent": float,
        "mem_total": int, "mem_used": int, "swap_used": int,
        "gpu": {"mps_mem_used": int, "mps_mem_total": int}
      },
      "server": {
        "uptime_sec": float,
        "active_tasks": int,
        "requests_per_minute": float,
        "compute_enabled": bool
      }
    }
    """
    # --- system metrics ---
    system: dict[str, object] = {}
    if psutil is not None:
        cpu_pct = psutil.cpu_percent(interval=None)
        vm = psutil.virtual_memory()
        sm = psutil.swap_memory()
        system["cpu_percent"] = float(cpu_pct)
        system["mem_total"] = int(vm.total)
        system["mem_used"] = int(vm.used)
        system["swap_used"] = int(sm.used)

    # --- MPS / unified memory ---
    gpu = {}
    used = _mps_mem_used_bytes()
    if used is not None:
        gpu["mps_mem_used"] = int(used)
    total = _sysctl_bytes("hw.memsize")  # total unified memory (best available signal)
    if total is not None:
        gpu["mps_mem_total"] = int(total)
    if gpu:
        system["gpu"] = gpu

    # --- server counters / throughput ---
    uptime = max(0.0, time.time() - _BOOT_TIME)
    rpm = (_requests / max(1.0, uptime)) * 60.0
    server = {
        "uptime_sec": float(uptime),
        "active_tasks": int(_active_tasks),
        "requests_per_minute": float(rpm),
        "compute_enabled": bool(_compute_enabled),
    }

    return {"system": system, "server": server}

@router.get("/metrics/health")
def health():
    return {"ok": True, "uptime_sec": time.time() - _BOOT_TIME}
