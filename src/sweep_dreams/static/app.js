const API_ENDPOINT = "/api/check-location";

const statusEl = document.getElementById("status");
const resultEl = document.getElementById("result");
const coordsEl = document.getElementById("coords");
const tabsEl = document.getElementById("schedule-tabs");
const cardsEl = document.getElementById("schedule-cards");

const formatDateTime = (value, timeZone) => {
  const date = new Date(value);
  return new Intl.DateTimeFormat("en-US", {
    dateStyle: "full",
    timeStyle: "short",
    timeZone,
  }).format(date);
};

const setStatus = (message, kind = "info") => {
  statusEl.textContent = message;
  statusEl.className = `status${kind === "error" ? " error" : kind === "success" ? " success" : ""}`;
};

const renderResult = (payload) => {
  const schedules = payload?.schedules || [];
  const nextWindow = schedules[0];
  if (!schedules.length || !nextWindow?.schedule) {
    throw new Error("No schedule returned for this location.");
  }

  const { latitude, longitude } = payload.request_point || {};
  coordsEl.textContent = latitude && longitude ? `${latitude.toFixed(6)}, ${longitude.toFixed(6)}` : "N/A";

  tabsEl.innerHTML = "";
  cardsEl.innerHTML = "";

  const makeLabel = (s, index) =>
    s.block_side ||
    s.cnn_right_left ||
    s.corridor ||
    `Schedule ${index + 1}`;

  const showCard = (index) => {
    const tabs = tabsEl.querySelectorAll(".tab");
    const cards = cardsEl.querySelectorAll(".card");
    tabs.forEach((tab, i) => tab.classList.toggle("active", i === index));
    cards.forEach((card, i) => card.classList.toggle("active", i === index));
  };

  schedules.forEach((entry, index) => {
    const s = entry.schedule || {};
    const sweepStart = entry.next_sweep_start;
    const sweepEnd = entry.next_sweep_end;

    const tab = document.createElement("button");
    tab.className = `tab${index === 0 ? " active" : ""}`;
    tab.textContent = makeLabel(s, index);
    tab.setAttribute("role", "tab");
    tab.setAttribute("aria-selected", index === 0 ? "true" : "false");
    tab.addEventListener("click", () => {
      showCard(index);
      tabsEl.querySelectorAll(".tab").forEach((node, i) => node.setAttribute("aria-selected", i === index ? "true" : "false"));
    });
    tabsEl.appendChild(tab);

    const card = document.createElement("div");
    card.className = `card${index === 0 ? " active" : ""}`;
    card.innerHTML = `
      <h3>${makeLabel(s, index)}</h3>
      <p class="summary">Next sweep: ${formatDateTime(sweepStart, payload.timezone)} → ${formatDateTime(sweepEnd, payload.timezone)}</p>
      <div class="chip">${s.full_name || "Unknown schedule"}</div>
      <dl class="details">
        <div>
          <dt>Limits</dt>
          <dd>${s.limits || s.corridor || "N/A"}</dd>
        </div>
        <div>
          <dt>Block side</dt>
          <dd>${s.block_side || s.cnn_right_left || "Not specified"}</dd>
        </div>
        <div>
          <dt>Hours</dt>
          <dd>${s.from_hour ?? "?"}:00 → ${s.to_hour ?? "?"}:00</dd>
        </div>
        <div>
          <dt>Weekday</dt>
          <dd>${s.week_day || "N/A"}</dd>
        </div>
      </dl>
    `;
    cardsEl.appendChild(card);
  });

  resultEl.classList.remove("hidden");
  setStatus("Found a sweeping schedule for your location.", "success");
};

const lookupByCoordinates = async (latitude, longitude) => {
  setStatus("Looking up your block...", "info");

  const url = new URL(API_ENDPOINT, window.location.origin);
  url.searchParams.set("latitude", latitude);
  url.searchParams.set("longitude", longitude);

  try {
    const response = await fetch(url.toString(), { method: "GET" });
    if (!response.ok) {
      const detail = await response.text();
      throw new Error(`Lookup failed (${response.status}): ${detail || "Unknown error"}`);
    }

    const payload = await response.json();
    renderResult(payload);
  } catch (error) {
    console.error(error);
    setStatus(error.message || "Something went wrong during lookup.", "error");
    resultEl.classList.add("hidden");
  }
};

const requestLocation = () => {
  if (!("geolocation" in navigator)) {
    setStatus("Geolocation is not supported in this browser.", "error");
    return;
  }

  setStatus("Requesting your location...", "info");

  navigator.geolocation.getCurrentPosition(
    (position) => {
      const { latitude, longitude } = position.coords;
      lookupByCoordinates(latitude, longitude);
    },
    (error) => {
      const reason =
        {
          1: "Location permission was denied.",
          2: "Unable to determine your location. Please try again.",
          3: "Timed out while requesting location.",
        }[error.code] || "Could not access your location.";
      setStatus(reason, "error");
    },
    { enableHighAccuracy: true, maximumAge: 0, timeout: 10000 }
  );
};

document.getElementById("locate-btn")?.addEventListener("click", requestLocation);
