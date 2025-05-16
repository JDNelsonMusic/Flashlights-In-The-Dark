class ClientState {
  ClientState();
  int myIndex = 0;             // TODO: replace with QR-scan
  double clockOffsetMs = 0.0;  // rolling average from /sync
}

final client = ClientState();