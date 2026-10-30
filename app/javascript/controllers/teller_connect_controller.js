import { Controller } from "@hotwired/stimulus";

// Wraps the Teller Connect widget (https://teller.io/docs/guides/link).
// On success, fills the hidden form fields and submits -- the Rails
// controller never calls Teller itself; by the time this fires, the
// browser already holds a valid, usable access token.
export default class extends Controller {
  static targets = ["accessToken", "enrollmentId", "institutionName", "form"];
  static values = { applicationId: String, environment: String };

  connect() {
    this._connectionToken = (this._connectionToken ?? 0) + 1;
    const connectionToken = this._connectionToken;

    this.waitForTellerConnect()
      .then(() => {
        if (connectionToken !== this._connectionToken) return;

        this.tellerConnect = TellerConnect.setup({
          applicationId: this.applicationIdValue,
          environment: this.environmentValue,
          products: ["transactions", "balance"],
          onSuccess: (enrollment) => {
            this.accessTokenTarget.value = enrollment.accessToken;
            this.enrollmentIdTarget.value = enrollment.enrollment.id;
            this.institutionNameTarget.value =
              enrollment.enrollment.institution.name;
            this.formTarget.requestSubmit();
          },
        });
      })
      .catch((error) => {
        console.error("Failed to load Teller Connect script", error);
      });
  }

  disconnect() {
    this._connectionToken = (this._connectionToken ?? 0) + 1;
  }

  waitForTellerConnect() {
    if (typeof TellerConnect !== "undefined") {
      return Promise.resolve();
    }

    return new Promise((resolve, reject) => {
      let tellerScript = document.querySelector(
        'script[src*="cdn.teller.io/connect/connect.js"]',
      );

      // Reject if the CDN request stalls without firing load or error
      const timeoutId = window.setTimeout(() => {
        if (tellerScript) tellerScript.dataset.tellerConnectState = "error";
        reject(new Error("Timed out loading Teller Connect script"));
      }, 10_000);

      // Remove previously failed script so we can retry with a fresh element
      if (tellerScript?.dataset.tellerConnectState === "error") {
        tellerScript.remove();
        tellerScript = null;
      }

      if (!tellerScript) {
        tellerScript = document.createElement("script");
        tellerScript.src = "https://cdn.teller.io/connect/connect.js";
        tellerScript.async = true;
        tellerScript.dataset.tellerConnectState = "loading";
        document.head.appendChild(tellerScript);
      }

      tellerScript.addEventListener(
        "load",
        () => {
          window.clearTimeout(timeoutId);
          tellerScript.dataset.tellerConnectState = "loaded";
          resolve();
        },
        { once: true },
      );
      tellerScript.addEventListener(
        "error",
        () => {
          window.clearTimeout(timeoutId);
          tellerScript.dataset.tellerConnectState = "error";
          reject(new Error("Failed to load Teller Connect script"));
        },
        { once: true },
      );

      // Re-check after attaching listeners in case the script loaded between
      // the initial typeof check and listener attachment (avoids a permanently
      // pending promise on retry flows).
      if (typeof TellerConnect !== "undefined") {
        window.clearTimeout(timeoutId);
        resolve();
      }
    });
  }

  open() {
    this.tellerConnect?.open();
  }
}
