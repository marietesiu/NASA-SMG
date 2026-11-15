const DEFAULT_STATE = {
  catalog: null,
  missionId: "around_earth",
  difficulty: "normal",
  audioEnabled: true,
  audioVolume: 0.8,
  budgetLimit: 54.8,
  unitSystem: "SI",
  repairSpend: 0,
  selectedComponents: {},
  currentScreen: "menuScreen",
  screenHistory: []
};

const state = { ...DEFAULT_STATE };
const MISSION_FACTS = [
  "Mars Climate Orbiter was lost after a navigation data mismatch between imperial and metric units.",
  "Ariane 5 Flight 501 was lost when reused software encountered a numeric overflow.",
  "Apollo 11's guidance computer prioritized critical tasks during a flood of alarms.",
  "Dawn had xenon left for its ion engines, but ran out of hydrazine for pointing.",
  "NEAR Shoemaker's overly strict abort logic discarded fuel and delayed its arrival.",
  "Galileo's jammed high-gain antenna forced the mission to rely on a smaller backup.",
  "Curiosity landed autonomously because its radio signal took about 14 minutes to reach Earth.",
  "MRO used hundreds of shallow atmospheric passes to aerobrake into Mars orbit.",
  "Juno needs enormous solar wings because Jupiter receives far less sunlight than Earth.",
  "Apollo 13 conserved power by shutting down equipment and operating on a tiny electrical budget.",
  "Voyager 1 was recovered by moving software functions across healthy memory regions.",
  "A solar conjunction can interrupt radio communications with Mars for days at a time.",
  "Cold gas thrusters are simple and reliable, while high-performance bipropellants need more complex plumbing.",
  "A small CubeSat can reach the Moon on a long, low-energy route instead of a fast direct transfer."
];
const choiceFlow = { step: "", fact: "", incident: null };
let transitFrameSource = null;
let transitSession = null;

function showScreen(screenId, options = {}) {
  const { pushHistory = true, force = false } = options;

  if (screenId && state.currentScreen !== screenId && pushHistory && !force) {
    state.screenHistory.push(state.currentScreen);
  }

  document.querySelectorAll(".screen").forEach((el) => {
    el.classList.toggle("active", el.id === screenId);
  });
  state.currentScreen = screenId;
  document.dispatchEvent(new CustomEvent("app:screen-changed", { detail: { screenId } }));
}

function goBack() {
  const previousScreen = state.screenHistory.pop() || "menuScreen";
  showScreen(previousScreen, { pushHistory: false, force: true });
}

async function resetEverything() {
  try {
    await fetch("/api/reset", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({})
    });
  } catch (_error) {
    // The launcher may be unavailable; the page reset still proceeds.
  }

  state.screenHistory = [];
  state.currentScreen = "menuScreen";
  showScreen("menuScreen", { pushHistory: false, force: true });
  window.location.reload();
}

window.showAppScreen = showScreen;
window.goBack = goBack;
window.resetEverything = resetEverything;

function formatMillions(value) {
  return `${Number(value || 0).toFixed(1)} M$`;
}

function formatKg(value) {
  return `${Math.round(Number(value || 0)).toLocaleString()} kg`;
}

function formatSeconds(value) {
  return `${Number(value || 0).toFixed(1)} s`;
}

function getSelectedComponent(categoryId) {
  return state.selectedComponents[categoryId] || null;
}

function getCategoryOption(categoryId, optionId) {
  const category = state.catalog.categories.find((item) => item.id === categoryId);
  if (!category) return null;
  return category.options.find((opt) => opt.id === optionId) || null;
}

function getMission() {
  return state.catalog.missions.find((mission) => mission.id === state.missionId) || state.catalog.missions[0];
}

function getDifficulty() {
  return state.catalog.difficulties[state.difficulty] || state.catalog.difficulties.normal;
}

function updateBudgetLimit() {
  const mission = getMission();
  const difficulty = getDifficulty();
  state.budgetLimit = 54.8 * (1 + Number(mission.budget_bonus || 0))
    * Number(difficulty.budget_multiplier || 1);
}

function ensureSelections() {
  state.catalog.categories.forEach((category) => {
    if (!state.selectedComponents[category.id]) {
      state.selectedComponents[category.id] = category.options[1]?.id || category.options[0]?.id || "";
    }
  });
}

function computeCategoryCost(categoryId) {
  const optionId = getSelectedComponent(categoryId);
  const option = getCategoryOption(categoryId, optionId);
  return option ? Number(option.cost_m || 0) : 0;
}

function getMissionWarningText() {
  const mission = getMission();
  if (mission.id !== "delivering_to_mars") {
    return "";
  }
  return "Mars cargo: +200 kg additional payload. This shipment contains radioactive material and requires special handling.";
}

function computeVehicleStats() {
  let dryMass = 0;
  let propellant = 0;
  let thrust = 0;
  let thrustVac = 0;
  let ispVac = 0;
  let qAlphaLimit = 0;
  let tankPressureLimit = 0;
  let heatLimit = 0;
  const mission = getMission();

  if (mission.id === "delivering_to_mars") {
    dryMass += 200;
  }

  state.catalog.categories.forEach((category) => {
    const option = getCategoryOption(category.id, getSelectedComponent(category.id));
    if (!option) return;
    const physics = option.physics || {};
    dryMass += Number(physics.dry_mass || 0);
    if (["propellant_tanks", "side_boosters"].includes(category.id)) {
      propellant += Number(physics.propellant || 0);
    }
    if (["main_engines", "side_boosters"].includes(category.id)) {
      thrust += Number(physics.thrust_sl || 0);
      thrustVac += Number(physics.thrust_vac || 0);
      ispVac = Math.max(ispVac, Number(physics.isp_vac || 0));
    }
    if (Number(physics.q_alpha_limit || 0) > 0) {
      qAlphaLimit = qAlphaLimit === 0 ? Number(physics.q_alpha_limit) : Math.min(qAlphaLimit, Number(physics.q_alpha_limit));
    }
    if (category.id === "thermal_protection" && Number(physics.heat_limit || 0) > 0) {
      heatLimit = heatLimit === 0 ? Number(physics.heat_limit) : Math.min(heatLimit, Number(physics.heat_limit));
    }
    if (["bulk_plates", "core_structure", "propellant_tanks"].includes(category.id)
        && Number(physics.tank_limit || 0) > 0) {
      tankPressureLimit = tankPressureLimit === 0
        ? Number(physics.tank_limit)
        : Math.min(tankPressureLimit, Number(physics.tank_limit));
    }
  });

  const difficulty = getDifficulty();
  const hazardMultiplier = Math.max(Number(difficulty.hazard || 1), 0.01);
  const fuelMultiplier = difficulty.fuel || 1;
  const effectivePropellant = propellant * fuelMultiplier;
  const twr = thrust > 0 ? (thrust / ((dryMass + effectivePropellant) * 9.81)) : 0;

  return {
    dryMass,
    propellant: effectivePropellant,
    thrust,
    thrustVac,
    ispVac,
    twr,
    qAlphaLimit: qAlphaLimit / hazardMultiplier,
    tankPressureLimit: tankPressureLimit / hazardMultiplier,
    heatLimit: heatLimit / hazardMultiplier,
    totalCost: state.catalog.categories.reduce((sum, category) => sum + computeCategoryCost(category.id), 0),
    mission,
    difficulty,
    cargoMassKg: mission.id === "delivering_to_mars" ? 200 : 0,
    radioactiveMaterial: mission.id === "delivering_to_mars"
  };
}

function renderMissionList() {
  const missionSelect = document.getElementById("missionSelect");
  missionSelect.innerHTML = state.catalog.missions
    .map((mission) => `
      <option value="${mission.id}" ${mission.id === state.missionId ? "selected" : ""}>${mission.name}</option>
    `)
    .join("");
}

function renderDifficultyList() {
  const difficultySelect = document.getElementById("difficultySelect");
  difficultySelect.innerHTML = Object.entries(state.catalog.difficulties)
    .map(([key, value]) => `
      <option value="${key}" ${key === state.difficulty ? "selected" : ""}>${value.label}</option>
    `)
    .join("");
}

function renderBudgetBar() {
  const stats = computeVehicleStats();
  const limit = Number(state.budgetLimit || 1);
  const displayedSpend = stats.totalCost + state.repairSpend;
  const fillPercent = Math.min((displayedSpend / limit) * 100, 100);
  const fill = document.getElementById("budgetBar");
  fill.style.width = `${fillPercent}%`;
  const repairNote = state.repairSpend > 0 ? ` (${state.repairSpend.toFixed(1)} repairs)` : "";
  document.getElementById("budgetText").textContent = `${displayedSpend.toFixed(1)} / ${limit.toFixed(1)} M$${repairNote}`;

  const budgetStatus = fillPercent > 100 ? "over" : fillPercent > 75 ? "warning" : "ok";
  fill.style.background = budgetStatus === "ok"
    ? "linear-gradient(90deg, #7ce6b1, #6ce3ff)"
    : budgetStatus === "warning"
      ? "linear-gradient(90deg, #f7bf64, #ffb36b)"
      : "linear-gradient(90deg, #ff6c7b, #ff4d5e)";
}

function renderCategoryList() {
  const container = document.getElementById("categoryList");
  container.innerHTML = state.catalog.categories.map((category) => {
    const selectedId = getSelectedComponent(category.id);
    const selectedOption = category.options.find((option) => option.id === selectedId) || category.options[1] || category.options[0];
    const cards = category.options.map((option) => {
      const selected = option.id === selectedOption.id;
      return `
        <button class="option-card ${selected ? "selected" : ""}" data-category="${category.id}" data-option="${option.id}" type="button">
          <strong>${option.name}</strong>
          <small>${option.tier}</small>
          <small>${formatMillions(option.cost_m)} • ${option.description}</small>
        </button>
      `;
    }).join("");

    return `
      <div class="category-card">
        <div class="category-head">
          <h4>${category.name}</h4>
          <span>${formatMillions(computeCategoryCost(category.id))}</span>
        </div>
        <div class="option-grid">${cards}</div>
      </div>
    `;
  }).join("");

  document.querySelectorAll(".option-card").forEach((button) => {
    button.addEventListener("click", () => {
      const { category, option } = button.dataset;
      state.selectedComponents[category] = option;
      renderCategoryList();
      renderBudgetBar();
      renderSummary();
    });
  });
}

function renderSummary() {
  const stats = computeVehicleStats();
  document.getElementById("dryMassValue").textContent = formatKg(stats.dryMass);
  document.getElementById("propellantValue").textContent = formatKg(stats.propellant);
  document.getElementById("thrustValue").textContent = `${Math.round(stats.thrust).toLocaleString()} N`;
  document.getElementById("ispValue").textContent = `${Number(stats.ispVac || 0).toFixed(0)} s`;
  document.getElementById("twrValue").textContent = stats.twr.toFixed(2);
  document.getElementById("structureValue").textContent = `${Math.round(stats.qAlphaLimit || 0).toLocaleString()} Pa·rad`;
  document.getElementById("tankPressureValue").textContent = `${Math.round(stats.tankPressureLimit || 0).toLocaleString()} Pa`;
  document.getElementById("thermalValue").textContent = `${Math.round(stats.heatLimit || 0).toLocaleString()} W/m²`;
  document.getElementById("difficultyDescription").textContent = stats.difficulty.description;

  const mission = getMission();
  const missionWarning = document.getElementById("missionWarning");
  const warningText = getMissionWarningText();
  missionWarning.textContent = warningText;
  missionWarning.hidden = !warningText;

  document.getElementById("missionSummaryName").textContent = mission.name;
  document.getElementById("missionSummaryTarget").textContent = mission.name;
  document.getElementById("missionSummaryDifficulty").textContent = getDifficulty().label;
  document.getElementById("missionSummaryBudget").textContent = `${state.budgetLimit.toFixed(1)} M$`;
  const supported = mission.supported_by_runtime === true;
  document.getElementById("missionSummaryLaunch").textContent = supported ? "Ready" : "Transfer model needed";
  const launchButton = document.getElementById("launchSimBtn");
  launchButton.disabled = !supported;
  launchButton.title = supported ? "" : "The current GMAT model supports circular Earth orbits only.";
}

function renderMissionInfo() {
  renderMissionList();
  renderDifficultyList();
  renderCategoryList();
  renderBudgetBar();
  renderSummary();
}

function updateLaunchMessage(text) {
  document.getElementById("launchMessage").textContent = text;
}

function renderChoiceDialog() {
  const title = document.getElementById("choiceTitle");
  const eyebrow = document.getElementById("choiceEyebrow");
  const description = document.getElementById("choiceDescription");
  const options = document.getElementById("choiceOptions");
  const fact = document.getElementById("choiceFact");
  const continueButton = document.getElementById("choiceContinueBtn");
  options.replaceChildren();
  fact.textContent = `Fun fact: ${choiceFlow.fact}`;
  fact.hidden = false;

  if (choiceFlow.step === "units") {
    eyebrow.textContent = "Preflight review / 01";
    title.textContent = "Choose a unit standard";
    description.textContent = "Set the convention for this mission's paperwork.";
    ["SI", "US customary"].forEach((unit) => {
      const option = document.createElement("button");
      option.type = "button";
      option.className = `choice-option ${state.unitSystem === unit ? "selected" : ""}`;
      option.textContent = unit;
      option.setAttribute("aria-pressed", String(state.unitSystem === unit));
      option.addEventListener("click", () => {
        state.unitSystem = unit;
        renderChoiceDialog();
      });
      options.append(option);
    });
    continueButton.textContent = "Continue to inspection";
    continueButton.hidden = false;
  } else {
    const { category, repairCost } = choiceFlow.incident;
    eyebrow.textContent = "Preflight review / 02";
    title.textContent = "Inspection discrepancy";
    description.textContent = `${category.name} has been flagged for a possible fault. Replace it for ${formatMillions(repairCost)}, or continue without the repair?`;
    const replaceButton = document.createElement("button");
    replaceButton.type = "button";
    replaceButton.className = "choice-option selected";
    replaceButton.textContent = `Replace component · ${formatMillions(repairCost)}`;
    replaceButton.addEventListener("click", () => resolveIncident(true));
    const skipButton = document.createElement("button");
    skipButton.type = "button";
    skipButton.className = "choice-option";
    skipButton.textContent = "Continue without repair";
    skipButton.addEventListener("click", () => resolveIncident(false));
    options.append(replaceButton, skipButton);
    continueButton.hidden = true;
  }
}

function beginMissionChoices() {
  choiceFlow.step = "units";
  choiceFlow.fact = MISSION_FACTS[Math.floor(Math.random() * MISSION_FACTS.length)];
  choiceFlow.incident = null;
  renderChoiceDialog();
  document.getElementById("missionChoiceDialog").showModal();
}

function continueMissionChoices() {
  const category = state.catalog.categories[Math.floor(Math.random() * state.catalog.categories.length)];
  const option = getCategoryOption(category.id, getSelectedComponent(category.id));
  const baseCost = Number(option?.cost_m || 1);
  choiceFlow.incident = {
    category,
    repairCost: Math.max(0.2, Math.min(3, baseCost * (0.04 + Math.random() * 0.06)))
  };
  choiceFlow.fact = MISSION_FACTS[Math.floor(Math.random() * MISSION_FACTS.length)];
  choiceFlow.step = "incident";
  renderChoiceDialog();
}

function resolveIncident(repaired) {
  document.getElementById("missionChoiceDialog").close();
  if (repaired) {
    state.repairSpend += choiceFlow.incident.repairCost;
    renderBudgetBar();
    launchMission();
    return;
  }

  if (Math.random() < 0.25) {
    document.getElementById("launchBadge").textContent = "Mission terminated";
    document.getElementById("launchTitle").textContent = "Mission failed";
    updateLaunchMessage(`A fault in the ${choiceFlow.incident.category.name} caused mission loss after the repair was deferred. No launch order was sent.`);
    document.getElementById("runtimeStatus").textContent = "Mission failed";
    showScreen("launchScreen");
    return;
  }

  launchMission();
}

function formatTransitCoefficient(value) {
  return Number(value).toPrecision(7);
}

function renderTransitSession(session) {
  if (!session || !["easy", "normal"].includes(String(session.difficulty).toLowerCase())) return;
  transitSession = session;
  document.getElementById("transitDifficulty").textContent = session.difficulty[0].toUpperCase() + session.difficulty.slice(1);
  document.getElementById("transitDestination").textContent = session.destination;
  document.getElementById("transitRocketEquation").textContent = "y = tan(θ) · x";
  document.getElementById("transitDestinationEquation").textContent =
    `y = (${formatTransitCoefficient(session.a)})x² + (${formatTransitCoefficient(session.b)})x + (${formatTransitCoefficient(session.c)})`;
  document.getElementById("transitTargetX").textContent = `${Number(session.target_x_km).toLocaleString(undefined, { maximumFractionDigits: 2 })} km`;
  const form = document.getElementById("transitAnswerForm");
  const feedback = document.getElementById("transitFeedback");
  const accepting = ["ready", "missed", "hit", "answer_received"].includes(String(session.status || "").toLowerCase());
  form.hidden = !accepting;
  document.getElementById("transitSubmitBtn").disabled = !accepting;
  feedback.textContent = session.feedback || (session.status === "answer_received"
    ? "Checking the angle…"
    : "Calculate the angle at the displayed destination distance." );
  showScreen("transitScreen");
}

async function pollTransitSession() {
  try {
    const response = await fetch("/api/transit/state", { cache: "no-store" });
    const result = await response.json();
    if (response.ok && result.session) renderTransitSession(result.session);
  } catch (_error) {
    // The local launcher may not be running while the static page is open.
  }
  window.setTimeout(pollTransitSession, 500);
}

async function submitTransitAnswer(event) {
  event.preventDefault();
  if (!transitSession) return;
  const angle = Number(document.getElementById("transitAngleInput").value);
  if (!Number.isFinite(angle) || angle <= -89 || angle >= 89) return;
  const message = {
    type: "transit-answer",
    session_id: transitSession.session_id,
    angle_deg: angle
  };

  try {
    if (transitFrameSource) {
      transitFrameSource.postMessage(message, window.location.origin);
    } else {
      const response = await fetch("/api/transit/answer", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(message)
      });
      const result = await response.json();
      if (!response.ok || result.ok === false) throw new Error(result.error || "The angle could not be sent.");
    }
    renderTransitSession({ ...transitSession, status: "answer_received", feedback: "Checking the angle…" });
  } catch (error) {
    document.getElementById("transitFeedback").textContent = `Submission error: ${error.message}`;
  }
}

function handleTransitBridgeMessage(event) {
  if (event.origin !== window.location.origin || !event.data || typeof event.data !== "object") return;
  if (event.data.type === "transit-start" && event.data.payload) {
    transitFrameSource = event.source;
    renderTransitSession({ ...event.data.payload, status: "ready", feedback: "Calculate the angle at the displayed destination distance." });
  } else if (event.data.type === "transit-result" && event.data.payload && transitSession
      && event.data.payload.session_id === transitSession.session_id) {
    renderTransitSession({ ...transitSession, status: "ready", feedback: event.data.payload.feedback });
  }
}

async function loadCatalog() {
  const response = await fetch("/api/catalog");
  const catalog = await response.json();
  state.catalog = catalog;
  state.missionId = catalog.missions[0].id;
  state.difficulty = "normal";
  updateBudgetLimit();
  ensureSelections();
  renderMissionInfo();
}

async function launchMission() {
  const mission = getMission();
  const payload = {
    mission_id: state.missionId,
    difficulty: state.difficulty,
    audio_enabled: state.audioEnabled,
    audio_volume: state.audioVolume,
    budget_limit_m: state.budgetLimit,
    selected_components: state.selectedComponents,
    mission_name: mission.name,
    cargo_mass_kg: mission.id === "delivering_to_mars" ? 200 : 0,
    radioactive_material: mission.id === "delivering_to_mars",
    cargo_warning: mission.id === "delivering_to_mars"
      ? "Mars mission cargo includes 200 kg of radioactive material."
      : ""
  };

  document.getElementById("launchBadge").textContent = "Simulation status";
  document.getElementById("launchTitle").textContent = "Mission launched in Godot";
  updateLaunchMessage("Sending mission to the local Godot launcher…");
  showScreen("launchScreen");

  try {
    const response = await fetch("/api/launch", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });

    const result = await response.json();
    if (!response.ok || result.ok === false) {
      throw new Error(result.error || "The launch request failed.");
    }

    updateLaunchMessage(`Mission accepted: ${result.config_path}. Godot is launching in native mode.`);
    transitSession = null;
    transitFrameSource = null;
  } catch (error) {
    updateLaunchMessage(`Launch error: ${error.message}`);
  }
}

function bindEvents() {
  document.getElementById("startMissionBtn").addEventListener("click", () => showScreen("builderScreen"));
  document.getElementById("showBuilderBtn").addEventListener("click", () => showScreen("builderScreen"));
  document.getElementById("showSettingsBtn").addEventListener("click", () => showScreen("settingsScreen"));
  document.getElementById("openInterceptBtn").addEventListener("click", () => showScreen("interceptScreen"));
  document.getElementById("backToMenuBtn").addEventListener("click", () => goBack());
  document.getElementById("settingsBackBtn").addEventListener("click", () => goBack());
  document.getElementById("launchBackBtn").addEventListener("click", () => goBack());
  document.getElementById("launchAgainBtn").addEventListener("click", beginMissionChoices);
  document.getElementById("settingsFromBuilderBtn").addEventListener("click", () => showScreen("settingsScreen"));
  document.getElementById("transitBackBtn").addEventListener("click", () => goBack());
  document.getElementById("globalResetBtn").addEventListener("click", resetEverything);
  document.getElementById("transitAnswerForm").addEventListener("submit", submitTransitAnswer);
  window.addEventListener("message", handleTransitBridgeMessage);

  document.getElementById("missionSelect").addEventListener("change", (event) => {
    state.missionId = event.target.value;
    updateBudgetLimit();
    renderBudgetBar();
    renderSummary();
  });

  document.getElementById("difficultySelect").addEventListener("change", (event) => {
    state.difficulty = event.target.value;
    updateBudgetLimit();
    renderBudgetBar();
    renderSummary();
  });

  document.getElementById("audioEnabled").addEventListener("change", (event) => {
    state.audioEnabled = event.target.checked;
  });

  document.getElementById("volumeSlider").addEventListener("input", (event) => {
    state.audioVolume = Number(event.target.value);
  });

  document.getElementById("launchSimBtn").addEventListener("click", beginMissionChoices);
  document.getElementById("choiceContinueBtn").addEventListener("click", continueMissionChoices);
  document.getElementById("choiceCancelBtn").addEventListener("click", () => {
    document.getElementById("missionChoiceDialog").close();
  });
}

window.addEventListener("DOMContentLoaded", async () => {
  bindEvents();
  await loadCatalog();
  showScreen("menuScreen");
  pollTransitSession();
});
