# Flashlights public resource review — 2026-08-29

Reference: `FITD-PUBLIC-2026-08-29`

## Approved for public exposure in this release

The user approved these seven February 2026 practice links for the public singer home:

| Resource | Public URL |
| --- | --- |
| Shadow Chorus — Sopranos | https://youtu.be/DD_Q9AGe3Vg |
| Shadow Chorus — Altos | https://youtu.be/8Sq4xGM-6xc |
| Shadow Chorus — Baritones | https://youtu.be/Bwhv9A7p63M |
| Light Chorus — Sopranos 1–2 | https://youtu.be/Xpy339h5v4U |
| Light Chorus — Altos 1–2 | https://youtu.be/PjMFdOPk3Zw |
| Light Chorus — Tenor/Bass | https://youtu.be/STO9SbsjrlY |
| All voices without electronics | https://youtu.be/xEPj1p83vHY |

The existing 13-part mixer and its already-integrated rehearsal audio assets are also approved to remain publicly available through the advanced mixer route.

## Resource-hub interface additions reviewed on 2026-08-29

The redesigned landing page and singer guide add only authored React, HTML, and CSS; technical text derived from this repository's current performer-app and concert-readiness documentation; one original device pictogram; and one inline Android platform mark. They do not add a score, recording, photograph, font file, or autoplaying media.

- The Apple-device destination uses an original, generic phone-and-tablet outline beside visible “Apple devices,” “iPhone,” and “iPad” text. It deliberately does not reproduce the standalone Apple logo.
- No App Store or Google Play download badge is used. This avoids implying a public-store release while the current destinations are TestFlight and Google Play testing links. The visible footer carries the applicable Apple and Google trademark notices.
- The Android mark is reproduced for platform identification under Google's Android brand guidance. The footer includes the Android trademark notice; this review record preserves the icon source and use context.
- The theme controls, solfège reference, electronics overview, and legacy-resource labels are original interface content for this release.

The public build must continue to exclude every asset listed below. A build is releasable only when the public-artifact assertion confirms that no unapproved media entered the dependency graph.

## Explicitly excluded from public exposure

The following resources are not approved for public exposure in this release and must remain honest, non-interactive placeholders with no asset URL:

- Any real score PDF, including score files already present elsewhere in the repository.
- Clare’s warm-up videos.
- The unlisted Flashlights presentation or demonstration video.

Each excluded resource requires a separate public-exposure decision. Future videos also require verified captions and complete transcripts before activation. A future public score must pass manifest validation as exactly 12 pages of 8.5×11 US Letter reader-order content and must record its file size before its download state may be marked `ready`.
