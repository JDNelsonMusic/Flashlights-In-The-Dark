# Package and Firebase release gates

The package is published privately to GitHub Packages as `@keex-ai-inc/flashlights-communiti-surface`. Consumers must pin a released version and import both the component and `@keex-ai-inc/flashlights-communiti-surface/style.css`.

The standalone Firebase site is public. Before deployment, record a content-rights review that approves every included score, audio, image, PDF, and video asset. Do not deploy if any asset is rehearsal-only, licensed for a closed group, or lacks public distribution permission.

After review, run the `publish-flashlights-surface` workflow manually with:

- a non-empty rights-review reference;
- the Firebase project ID;
- the Firebase Hosting site ID; and
- CI-held Firebase credentials in `FIREBASE_SERVICE_ACCOUNT`.

The workflow maps the checked-in `flashlights-public` target to the supplied Hosting site immediately before deployment. No Firebase project identifier or credential is stored in the repository.
