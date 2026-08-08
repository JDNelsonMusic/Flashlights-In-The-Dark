"""PyQt-based desktop application for Light Chorus MIDI processing."""
from __future__ import annotations

import sys
from pathlib import Path

from PyQt6.QtCore import Qt, QUrl
from PyQt6.QtGui import QDesktopServices
from PyQt6.QtWidgets import (
    QApplication,
    QComboBox,
    QFileDialog,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QPlainTextEdit,
    QWidget,
)

from .processor import ProcessingOptions, process_midi_to_workbook

APP_TITLE = "Flashlights Light Chorus Builder"
DEFAULT_OUTPUT_NAME = "LightChorusEvents.xlsx"


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle(APP_TITLE)
        self.resize(720, 420)

        container = QWidget(self)
        self.setCentralWidget(container)

        layout = QGridLayout()
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setHorizontalSpacing(12)
        layout.setVerticalSpacing(12)
        container.setLayout(layout)

        # MIDI file chooser row
        self.midi_path_edit = QLineEdit(self)
        self.midi_path_edit.setReadOnly(True)
        browse_midi_button = QPushButton("Browse…", self)
        browse_midi_button.clicked.connect(self._select_midi_file)

        midi_row = QHBoxLayout()
        midi_row.addWidget(self.midi_path_edit)
        midi_row.addWidget(browse_midi_button)

        layout.addWidget(QLabel("Input MIDI file"), 0, 0)
        layout.addLayout(midi_row, 0, 1)

        # Output path selectors
        self.output_path_edit = QLineEdit(self)
        self.output_path_edit.setText(str(Path.cwd() / DEFAULT_OUTPUT_NAME))
        browse_output_button = QPushButton("Choose…", self)
        browse_output_button.clicked.connect(self._select_output_path)

        output_row = QHBoxLayout()
        output_row.addWidget(self.output_path_edit)
        output_row.addWidget(browse_output_button)

        layout.addWidget(QLabel("Output spreadsheet"), 1, 0)
        layout.addLayout(output_row, 1, 1)

        # Octave numbering mode
        self.octave_combo = QComboBox(self)
        self.octave_combo.addItem("Scientific (C4 = MIDI 60)", -1)
        self.octave_combo.addItem("Project legacy (C5 = MIDI 60)", 0)
        layout.addWidget(QLabel("Octave numbering"), 2, 0)
        layout.addWidget(self.octave_combo, 2, 1)

        # Action buttons
        self.generate_button = QPushButton("Generate Spreadsheet", self)
        self.generate_button.clicked.connect(self._generate)
        self.open_button = QPushButton("Reveal Output", self)
        self.open_button.clicked.connect(self._reveal_output)
        self.open_button.setEnabled(False)

        button_row = QHBoxLayout()
        button_row.addWidget(self.generate_button)
        button_row.addWidget(self.open_button)
        button_row.addStretch(1)

        layout.addLayout(button_row, 3, 0, 1, 2)

        # Status console
        self.status_console = QPlainTextEdit(self)
        self.status_console.setReadOnly(True)
        self.status_console.setPlaceholderText("Status messages will appear here…")
        layout.addWidget(self.status_console, 4, 0, 1, 2)

        self._last_output_path: Path | None = None

    # --- UI helpers -------------------------------------------------
    def _select_midi_file(self) -> None:
        start_dir = Path(self.midi_path_edit.text()).parent if self.midi_path_edit.text() else Path.cwd()
        path, _ = QFileDialog.getOpenFileName(
            self,
            "Choose Light Chorus MIDI file",
            str(start_dir),
            "MIDI files (*.mid *.midi)"
        )
        if path:
            self.midi_path_edit.setText(path)
            # Suggest output name alongside the MIDI location
            midi_path = Path(path)
            suggested_output = midi_path.with_suffix(".light_chorus.xlsx")
            self.output_path_edit.setText(str(suggested_output))
            self._log(f"Selected MIDI: {midi_path}")

    def _select_output_path(self) -> None:
        initial = self.output_path_edit.text() or str(Path.cwd() / DEFAULT_OUTPUT_NAME)
        path, _ = QFileDialog.getSaveFileName(
            self,
            "Save spreadsheet as…",
            initial,
            "Excel workbook (*.xlsx)"
        )
        if path:
            if not path.lower().endswith(".xlsx"):
                path += ".xlsx"
            self.output_path_edit.setText(path)
            self._log(f"Output path set to {path}")

    def _generate(self) -> None:
        midi_path_text = self.midi_path_edit.text().strip()
        output_path_text = self.output_path_edit.text().strip()

        if not midi_path_text:
            QMessageBox.warning(self, APP_TITLE, "Select a MIDI file before generating the spreadsheet.")
            return

        midi_path = Path(midi_path_text)
        if not midi_path.exists():
            QMessageBox.warning(self, APP_TITLE, "The selected MIDI path does not exist anymore.")
            return

        if not output_path_text:
            QMessageBox.warning(self, APP_TITLE, "Provide a destination for the spreadsheet output.")
            return

        output_path = Path(output_path_text)
        output_path.parent.mkdir(parents=True, exist_ok=True)

        octave_offset = self.octave_combo.currentData()
        options = ProcessingOptions(octave_offset=octave_offset)

        self._log("Starting conversion…")
        self.generate_button.setEnabled(False)
        QApplication.setOverrideCursor(Qt.CursorShape.WaitCursor)
        try:
            workbook = process_midi_to_workbook(str(midi_path), str(output_path), options=options)
        except Exception as exc:  # noqa: BLE001
            QApplication.restoreOverrideCursor()
            self.generate_button.setEnabled(True)
            self._log(f"❌ Error: {exc}")
            QMessageBox.critical(self, APP_TITLE, f"Failed to build spreadsheet:\n{exc}")
            return

        QApplication.restoreOverrideCursor()
        self.generate_button.setEnabled(True)
        self._last_output_path = output_path
        self.open_button.setEnabled(True)
        self._log(f"✅ Created {output_path}")
        QMessageBox.information(self, APP_TITLE, "Spreadsheet generated successfully!")

    def _reveal_output(self) -> None:
        if not self._last_output_path or not self._last_output_path.exists():
            QMessageBox.information(self, APP_TITLE, "Build the spreadsheet first.")
            return
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(self._last_output_path.parent)))

    def _log(self, message: str) -> None:
        self.status_console.appendPlainText(message)


def run_app() -> None:
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    run_app()
