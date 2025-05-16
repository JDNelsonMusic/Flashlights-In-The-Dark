class ClientState {
  int myIndex = 0;           // hard-code for rehearsal
  double clockOffsetMs = 0;  // to be updated by /sync
}

final client = ClientState();