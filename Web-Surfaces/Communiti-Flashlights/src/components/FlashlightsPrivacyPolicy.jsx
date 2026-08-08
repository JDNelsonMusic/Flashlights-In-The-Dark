import React from 'react';

function FlashlightsPrivacyPolicy() {
  return (
    <article className="flashlights-privacy">
      <h3>Privacy Policy for Flashlights-ITD Client</h3>
      <p>
        <strong>Effective date:</strong> September 19, 2025
      </p>
      <p>
        <strong>Developer:</strong> KEEx AI INC
      </p>

      <section>
        <h4>Overview</h4>
        <p>
          Flashlights-ITD Client ("the App") is developed and maintained by KEEx AI INC. The App is
          designed for use in controlled rehearsals and performances to provide synchronized
          flashlight, audio, and network communication features for choir members.
        </p>
        <p>
          This Privacy Policy explains what information the App collects, how it is used, and how it
          is protected.
        </p>
      </section>

      <section>
        <h4>Information We Do Not Collect</h4>
        <ul>
          <li>
            The App does not collect, store, or share any personal information such as your name,
            email address, phone number, or location.
          </li>
          <li>The App does not include third-party advertising SDKs.</li>
          <li>The App does not track users across apps or services.</li>
        </ul>
      </section>

      <section>
        <h4>Information the App May Process</h4>
        <p>To function as intended in rehearsals and performances, the App may temporarily access:</p>
        <ul>
          <li>Device flashlight and screen brightness (to display synchronized cues).</li>
          <li>
            Microphone (only if explicitly enabled for rehearsal purposes). Audio is not stored,
            transmitted outside the rehearsal network, or shared with KEEx AI.
          </li>
          <li>
            Network communication (local Wi-Fi, multicast/unicast) to receive cues from the
            conductor's console. No personal data is transmitted.
          </li>
        </ul>
        <p>
          This data remains on the device or within the closed rehearsal network and is never
          uploaded to KEEx AI servers.
        </p>
      </section>

      <section>
        <h4>Permissions Used</h4>
        <ul>
          <li>Camera/flashlight: To control the device torch during cues.</li>
          <li>Microphone (optional, if enabled): To capture audio cues locally.</li>
          <li>
            Network/Wi-Fi access: To connect to the local conductor console for performance
            synchronization.
          </li>
          <li>Foreground service: To keep the app responsive during rehearsals and performances.</li>
        </ul>
      </section>

      <section>
        <h4>Data Sharing</h4>
        <p>KEEx AI does not sell, rent, or share any user data with third parties.</p>
      </section>

      <section>
        <h4>Security</h4>
        <p>
          Because the App does not collect personal data or transmit information externally, no
          personal information is at risk. All communication remains confined to the closed rehearsal
          Wi-Fi network.
        </p>
      </section>

      <section>
        <h4>Children's Privacy</h4>
        <p>
          The App is intended for use in rehearsals and performances under the guidance of a
          director. It does not knowingly collect personal information from children.
        </p>
      </section>

      <section>
        <h4>Changes to This Policy</h4>
        <p>
          KEEx AI may update this Privacy Policy if features change. Updates will be posted at the
          same URL.
        </p>
      </section>

      <section>
        <h4>Contact Us</h4>
        <p>If you have questions or concerns about this Privacy Policy, please contact:</p>
        <ul>
          <li>KEEx AI INC</li>
          <li>
            Email: <a href="mailto:jdn@keex.ai">jdn@keex.ai</a>
          </li>
          <li>
            Website: <a href="https://keex.ai" target="_blank" rel="noreferrer">https://keex.ai</a>
          </li>
        </ul>
      </section>
    </article>
  );
}

export default FlashlightsPrivacyPolicy;
