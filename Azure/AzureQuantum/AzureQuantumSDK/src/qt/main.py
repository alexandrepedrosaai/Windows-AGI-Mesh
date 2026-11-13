"""Qt main window for Windows-AGI-Mesh-QuantumSDK."""
import sys

def main():
    try:
        from PyQt6.QtWidgets import (QApplication, QMainWindow, QWidget,
                                      QVBoxLayout, QLabel, QPushButton, QTextEdit)
        from PyQt6.QtCore import Qt, QThreadPool
        from PyQt6.QtGui import QFont
        from .worker import QuantumWorker
        QT_AVAILABLE = True
    except ImportError:
        print("PyQt6 not installed. pip install PyQt6")
        QT_AVAILABLE = False

    if not QT_AVAILABLE:
        from src.python.core.contracts import ExperimentConfig
        from src.python.core.fake_service import FakeQuantumService
        config = ExperimentConfig(qubit_count=4, ancilla_count=2,
                                   theta_z=0.5, theta_y=0.3, shot_count=100)
        svc = FakeQuantumService()
        result = svc.run_experiment(config)
        print(f"Mean: {result.mean:.4f} | Dev: {result.deviation:.4f}")
        return 0

    app = QApplication(sys.argv)
    app.setApplicationName("Windows-AGI-Mesh-QuantumSDK")

    class MainWindow(QMainWindow):
        def __init__(self):
            super().__init__()
            self.setWindowTitle("Windows-AGI-Mesh-QuantumSDK v2.0")
            self.setMinimumSize(800, 600)
            self._pool = QThreadPool.globalInstance()
            central = QWidget()
            self.setCentralWidget(central)
            layout = QVBoxLayout(central)
            title = QLabel("Windows-AGI-Mesh-QuantumSDK")
            title.setFont(QFont("Arial", 16, QFont.Weight.Bold))
            title.setAlignment(Qt.AlignmentFlag.AlignCenter)
            layout.addWidget(title)
            btn = QPushButton("Run Experiment (4 qubits, 100 shots)")
            btn.clicked.connect(self._run)
            layout.addWidget(btn)
            self._out = QTextEdit()
            self._out.setReadOnly(True)
            layout.addWidget(self._out)

        def _run(self):
            self._out.append("Running...")
            w = QuantumWorker(4, 2, 0.5, 0.3, 100)
            w.signals.finished.connect(self._done)
            w.signals.error.connect(lambda e: self._out.append(f"Error: {e}"))
            self._pool.start(w)

        def _done(self, r):
            self._out.append(f"Mean: {r.get('mean',0):.4f} | Dev: {r.get('deviation',0):.4f}")
            self._out.append(f"Above threshold: {r.get('above_threshold',False)}")
            self._out.append("---")

    w = MainWindow()
    w.show()
    return app.exec()

if __name__ == "__main__":
    sys.exit(main())
