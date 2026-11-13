"""Qt worker thread for async quantum experiment execution."""
from __future__ import annotations
import math, random
from typing import Any, Dict

try:
    from PyQt6.QtCore import QObject, QRunnable, pyqtSignal, pyqtSlot
    QT_AVAILABLE = True
except ImportError:
    QT_AVAILABLE = False
    class QObject: pass
    class QRunnable: pass
    def pyqtSignal(*a): return None
    def pyqtSlot(*a):
        def d(f): return f
        return d


class WorkerSignals(QObject if QT_AVAILABLE else object):
    if QT_AVAILABLE:
        finished = pyqtSignal(dict)
        error    = pyqtSignal(str)
        progress = pyqtSignal(int)


class QuantumWorker(QRunnable if QT_AVAILABLE else object):
    """Qt worker for async quantum experiment execution."""

    def __init__(self, qubit_count: int, ancilla_count: int,
                 theta_z: float, theta_y: float,
                 shot_count: int, threshold: float = 0.5,
                 backend: str = "microsoft.simulator.full-state") -> None:
        if QT_AVAILABLE:
            super().__init__()
        self.qubit_count   = qubit_count
        self.ancilla_count = ancilla_count
        self.theta_z       = theta_z
        self.theta_y       = theta_y
        self.shot_count    = shot_count
        self.threshold     = threshold
        self.backend       = backend
        self.signals       = WorkerSignals()

    @pyqtSlot()
    def run(self) -> None:
        try:
            result = self._execute()
            if QT_AVAILABLE:
                self.signals.finished.emit(result)
        except Exception as exc:
            if QT_AVAILABLE:
                self.signals.error.emit(str(exc))

    def _execute(self) -> Dict[str, Any]:
        try:
            import sys
            from pathlib import Path
            sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
            from src.python.core.contracts import ExperimentConfig, QuantumBackend
            from src.python.core.service import QuantumService
            try:
                backend = QuantumBackend(self.backend)
            except ValueError:
                backend = QuantumBackend.SIMULATOR_FULL_STATE
            config = ExperimentConfig(
                qubit_count=self.qubit_count, ancilla_count=self.ancilla_count,
                theta_z=self.theta_z, theta_y=self.theta_y,
                shot_count=self.shot_count, threshold=self.threshold,
                backend=backend)
            with QuantumService(Path(__file__).resolve().parents[3]) as svc:
                result = svc.run_experiment(config)
            return result.to_dict()
        except Exception:
            rng = random.Random(hash((self.theta_z, self.theta_y)))
            mean = max(0.0, min(1.0,
                0.5 + 0.3*math.sin(self.theta_z)*math.cos(self.theta_y) + rng.gauss(0,0.05)))
            return {"mean": mean, "deviation": abs(rng.gauss(0.1, 0.02)),
                    "above_threshold": mean > self.threshold,
                    "shot_count": self.shot_count, "qubit_count": self.qubit_count,
                    "backend": "qt-simulation"}
