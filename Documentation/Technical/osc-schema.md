Schema-Version: 0.9.0
Last-Changed: 2025-05-15
Breaking-Change-Policy: bump major, deprecate old for ≥1 rehearsal

| Address      | Tag   | Arguments                             | Notes                  |
|--------------|-------|---------------------------------------|------------------------|
| /flash/on    | i f   | index:Int32, intensity:Float32 0–1    | Torch on               |
| /flash/off   | i     | index:Int32                           | Torch off              |
| /audio/play  | i s f | index:Int32, file:String, gain:Float32 0–1 | Play clip         |
| /audio/stop  | i     | index:Int32                           | Stop clip              |
| /mic/record  | i f   | index:Int32, maxDuration:Float32 seconds | Start rec         |
| /sync        | t     | timestamp:UInt64 (NTP)                | Sent every 0.2 s       |

[^1]: Based on the OSC 1.0 specification (https://opensoundcontrol.stanford.edu/spec-1_0.html) and the CNMAT time-tag convention for NTP timetags.

Why this layout:

This schema provides a concise and clear set of control and synchronization messages for flashlight and audio operations. Int32 and Float32 types ensure consistency across implementations, while the NTP timetag supports precise timing for synchronization.