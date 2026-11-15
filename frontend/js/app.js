const DEFAULT_STATE = {
  catalog: null,
  missionId: "around_earth",
  difficulty: "normal",
  audioEnabled: true,
  audioVolume: 0.8,
  budgetLimit: 54.8,
  selectedComponents: {},
  currentScreen: "menuScreen"
};

const state = { ...DEFAULT_STATE };

function showScreen(screenId) {
  document.querySelectorAll(".screen").forEach((el) => {
    el.classList.toggle("active", el.id === screenId);
  });
  state.currentScreen = screenId;
  document.dispatchEvent(new CustomEvent("app:screen-changed", { detail: { screenId } }));
}

window.showAppScreen = showScreen;

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
  const fillPercent = Math.min((stats.totalCost / limit) * 100, 100);
  const fill = document.getElementById("budgetBar");
  fill.style.width = `${fillPercent}%`;
  document.getElementById("budgetText").textContent = `${stats.totalCost.toFixed(1)} / ${limit.toFixed(1)} M$`;

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
  } catch (error) {
    updateLaunchMessage(`Launch error: ${error.message}`);
  }
}

function bindEvents() {
  document.getElementById("startMissionBtn").addEventListener("click", () => showScreen("builderScreen"));
  document.getElementById("showBuilderBtn").addEventListener("click", () => showScreen("builderScreen"));
  document.getElementById("showSettingsBtn").addEventListener("click", () => showScreen("settingsScreen"));
  document.getElementById("openInterceptBtn").addEventListener("click", () => showScreen("interceptScreen"));
  document.getElementById("backToMenuBtn").addEventListener("click", () => showScreen("menuScreen"));
  document.getElementById("settingsBackBtn").addEventListener("click", () => showScreen("builderScreen"));
  document.getElementById("launchBackBtn").addEventListener("click", () => showScreen("builderScreen"));
  document.getElementById("launchAgainBtn").addEventListener("click", () => launchMission());
  document.getElementById("settingsFromBuilderBtn").addEventListener("click", () => showScreen("settingsScreen"));

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

  document.getElementById("launchSimBtn").addEventListener("click", launchMission);
}

window.addEventListener("DOMContentLoaded", async () => {
  bindEvents();
  await loadCatalog();
  showScreen("menuScreen");
});
