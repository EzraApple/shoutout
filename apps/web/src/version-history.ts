import "@fontsource-variable/space-grotesk";
import "@fontsource/pixelify-sans/500.css";
import "@fontsource/pixelify-sans/600.css";
import posthog from "posthog-js";
import "./styles.css";

const posthogProjectKey = import.meta.env.VITE_POSTHOG_KEY?.trim();
const posthogHost = import.meta.env.VITE_POSTHOG_HOST?.trim() || "https://us.i.posthog.com";

if (posthogProjectKey) {
  posthog.init(posthogProjectKey, {
    api_host: posthogHost,
    autocapture: false,
    capture_pageview: true,
    disable_session_recording: true,
    person_profiles: "identified_only",
  });
}

const header = document.querySelector<HTMLElement>(".site-header");

const syncHeader = () => {
  header?.classList.toggle("is-floating", window.scrollY > 24);
};

syncHeader();
window.addEventListener("scroll", syncHeader, { passive: true });
