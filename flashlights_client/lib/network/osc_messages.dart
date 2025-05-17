/// OSC message definitions for Flutter
import 'package:osc/osc.dart';

enum OscAddress {
  flashOn('/flash/on'),
  flashOff('/flash/off'),
  audioPlay('/audio/play'),
  audioStop('/audio/stop'),
  micRecord('/mic/record'),
  sync('/sync');

  final String value;
  const OscAddress(this.value);
}

abstract class OscCodable {
  OscAddress get address;
  OSCMessage toOsc();
}

/// /flash/on - index:Int32, intensity:Float32
class FlashOn implements OscCodable {
  final int index;
  final double intensity;

  FlashOn(this.index, this.intensity);

  @override
  OscAddress get address => OscAddress.flashOn;

  @override
  OSCMessage toOsc() {
    return OSCMessage(address.value, [index, intensity]);
  }

  static FlashOn? fromOsc(OSCMessage message) {
    if (message.address != OscAddress.flashOn.value ||
        message.arguments.length != 2) {
      return null;
    }
    final arg0 = message.arguments[0];
    final arg1 = message.arguments[1];
    if (arg0 is int && arg1 is double) {
      return FlashOn(arg0, arg1);
    }
    return null;
  }
}

/// /flash/off - index:Int32
class FlashOff implements OscCodable {
  final int index;

  FlashOff(this.index);

  @override
  OscAddress get address => OscAddress.flashOff;

  @override
  OSCMessage toOsc() {
    return OSCMessage(address.value, [index]);
  }

  static FlashOff? fromOsc(OSCMessage message) {
    if (message.address != OscAddress.flashOff.value ||
        message.arguments.length != 1) {
      return null;
    }
    final arg0 = message.arguments[0];
    if (arg0 is int) {
      return FlashOff(arg0);
    }
    return null;
  }
}

/// /audio/play - index:Int32, file:String, gain:Float32
class AudioPlay implements OscCodable {
  final int index;
  final String file;
  final double gain;

  AudioPlay(this.index, this.file, this.gain);

  @override
  OscAddress get address => OscAddress.audioPlay;

  @override
  OSCMessage toOsc() {
    return OSCMessage(address.value, [index, file, gain]);
  }

  static AudioPlay? fromOsc(OSCMessage message) {
    if (message.address != OscAddress.audioPlay.value ||
        message.arguments.length != 3) {
      return null;
    }
    final arg0 = message.arguments[0];
    final arg1 = message.arguments[1];
    final arg2 = message.arguments[2];
    if (arg0 is int && arg1 is String && arg2 is double) {
      return AudioPlay(arg0, arg1, arg2);
    }
    return null;
  }
}

/// /audio/stop - index:Int32
class AudioStop implements OscCodable {
  final int index;

  AudioStop(this.index);

  @override
  OscAddress get address => OscAddress.audioStop;

  @override
  OSCMessage toOsc() {
    return OSCMessage(address.value, [index]);
  }

  static AudioStop? fromOsc(OSCMessage message) {
    if (message.address != OscAddress.audioStop.value ||
        message.arguments.length != 1) {
      return null;
    }
    final arg0 = message.arguments[0];
    if (arg0 is int) {
      return AudioStop(arg0);
    }
    return null;
  }
}

/// /mic/record - index:Int32, maxDuration:Float32
class MicRecord implements OscCodable {
  final int index;
  final double maxDuration;

  MicRecord(this.index, this.maxDuration);

  @override
  OscAddress get address => OscAddress.micRecord;

  @override
  OSCMessage toOsc() {
    return OSCMessage(address.value, [index, maxDuration]);
  }

  static MicRecord? fromOsc(OSCMessage message) {
    if (message.address != OscAddress.micRecord.value ||
        message.arguments.length != 2) {
      return null;
    }
    final arg0 = message.arguments[0];
    final arg1 = message.arguments[1];
    if (arg0 is int && arg1 is double) {
      return MicRecord(arg0, arg1);
    }
    return null;
  }
}

/// /sync - timestamp:UInt64 (NTP)
class SyncMessage implements OscCodable {
  final BigInt timestamp;

  SyncMessage(this.timestamp);

  @override
  OscAddress get address => OscAddress.sync;

  @override
  OSCMessage toOsc() {
    return OSCMessage(address.value, [timestamp]);
  }

  static SyncMessage? fromOsc(OSCMessage message) {
    if (message.address != OscAddress.sync.value ||
        message.arguments.length != 1) {
      return null;
    }
    final arg0 = message.arguments[0];
    if (arg0 is BigInt) {
      return SyncMessage(arg0);
    }
    return null;
  }
}

/// Helper for NTP timestamp
BigInt oscNow() {
  final eraOffset = BigInt.from(2208988800);
  final nowSecs = BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000);
  return eraOffset + nowSecs;
}

// TODO: Step 2.3 – integrate these models into the Flutter listener.