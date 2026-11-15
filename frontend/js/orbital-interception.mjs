import { DEFAULT_SCENARIO } from "./intercept-physics.mjs";
import { InterceptRenderer } from "./intercept-renderer.mjs";
import { InterceptSimulation } from "./intercept-simulation.mjs";

function formatPosition(position) {
  return `${Math.round(position.x)}, ${Math.round(position.y)} m`;
}

function describeOutcome(analysis) {
  if (analysis.status === "intercepted") {
    return `Interception confirmed at T+${analysis.collisionTime.toFixed(2)} s. Both centers were within ${analysis.collisionRadius.toFixed(1)} m at the same instant.`;
  }
  if (analysis.status === "no-region") {
    return "The rocket never entered the planet's horizontal orbital band before its ballistic flight ended. Change the launch vector to reach the target's downrange region.";
  }

  const horizontalOffset = analysis.closestRocket.x - analysis.closestPlanet.x;
  const verticalOffset = analysis.closestRocket.y - analysis.closestPlanet.y;
  if (Math.abs(verticalOffset) >= Math.abs(horizontalOffset)) {
    const direction = verticalOffset > 0 ? "above" : "below";
    return `The rocket passed ${direction} the planet. At closest approach the altitude separation was ${Math.abs(verticalOffset).toFixed(1)} m.`;
  }
  if (horizontalOffset > 0) {
    return `The rocket passed the planet's downrange position too early. It was ${horizontalOffset.toFixed(1)} m ahead at closest approach.`;
  }
  return `The rocket arrived too late to meet the planet's downrange position. The target was ${Math.abs(horizontalOffset).toFixed(1)} m ahead at closest approach.`;
}

function initializeInterception() {
  const canvas = document.getElementById("interceptCanvas");
  if (!canvas) return;

  let scenario = readScenarioInputs();
  const simulation = new InterceptSimulation(scenario);
  const renderer = new InterceptRenderer(canvas, scenario);
  const angleSlider = document.getElementById("launchAngleSlider");
  const angleValue = document.getElementById("launchAngleValue");
  const launchButton = document.getElementById("interceptLaunchBtn");
  const pauseButton = document.getElementById("interceptPauseBtn");
  const resetButton = document.getElementById("interceptResetBtn");
  const speedSelect = document.getElementById("simulationSpeedSelect");
  const metrics = document.getElementById("interceptResultMetrics");
  const feedback = document.getElementById("interceptFeedbackText");
  const control = new AbortController();
  const { signal } = control;
  let animationFrame = 0;
  let previousFrame = 0;

  function setFeedback() {
    if (!simulation.complete || !simulation.analysis || !simulation.solution) {
      metrics.hidden = true;
      return;
    }
    const analysis = simulation.analysis;
    feedback.textContent = describeOutcome(analysis);
    document.getElementById("interceptFeedback").dataset.result = analysis.status;
    document.getElementById("resultAngle").textContent = `${simulation.angleDegrees.toFixed(1)}°`;
    document.getElementById("resultDistance").textContent = `${analysis.minimumDistance.toFixed(2)} m`;
    document.getElementById("resultClosestTime").textContent = `T+${analysis.closestTime.toFixed(2)} s`;
    document.getElementById("resultOptimalAngle").textContent = simulation.solution.hasSolution
      ? `${simulation.solution.angleDegrees.toFixed(2)}°`
      : `No intercept in ${DEFAULT_SCENARIO.minAngle}°–${DEFAULT_SCENARIO.maxAngle}°`;
    const coordinateRow = document.getElementById("interceptCoordinatesRow");
    coordinateRow.hidden = analysis.status !== "intercepted";
    if (analysis.intercept) {
      document.getElementById("resultInterceptPoint").textContent = formatPosition(analysis.intercept);
    }
    metrics.hidden = false;
  }

  function updateReadouts() {
    const rocket = simulation.getRocketPosition();
    const planet = simulation.getPlanetPosition();
    document.getElementById("interceptTime").textContent = `T+ ${simulation.elapsed.toFixed(2)} s`;
    document.getElementById("rocketPositionReadout").textContent = formatPosition(rocket);
    document.getElementById("planetPositionReadout").textContent = formatPosition(planet);
    let status = "Awaiting launch";
    if (simulation.running && simulation.paused) status = "Paused";
    else if (simulation.running) status = "Ascent in progress";
    else if (simulation.complete) status = simulation.analysis.status === "intercepted" ? "Intercept confirmed" : "Flight complete";
    document.getElementById("flightStatusReadout").textContent = status;
    angleSlider.disabled = simulation.running;
    document.querySelectorAll(".scenario-fields input").forEach((input) => {
      input.disabled = simulation.running;
    });
    launchButton.disabled = simulation.running;
    launchButton.textContent = simulation.complete ? "Launch again" : "Launch rocket";
    pauseButton.disabled = !simulation.running;
    pauseButton.textContent = simulation.paused ? "Resume" : "Pause";
  }

  function resetFlight() {
    simulation.reset();
    angleSlider.value = "45";
    angleValue.value = "45.0";
    angleValue.textContent = "45.0";
    speedSelect.value = "1";
    feedback.textContent = "Choose an angle and launch to test a true time-dependent rendezvous.";
    document.getElementById("interceptFeedback").dataset.result = "";
    metrics.hidden = true;
    document.getElementById("interceptCoordinatesRow").hidden = true;
    updateReadouts();
    renderer.draw(simulation);
  }

  function drawFrame(timestamp) {
    const delta = previousFrame === 0 ? 0 : (timestamp - previousFrame) / 1000;
    previousFrame = timestamp;
    const wasComplete = simulation.complete;
    simulation.advance(delta);
    renderer.draw(simulation);
    updateReadouts();
    if (simulation.complete && !wasComplete) setFeedback();
    if (simulation.complete && simulation.elapsed >= simulation.scenario.duration) {
      animationFrame = 0;
      return;
    }
    animationFrame = window.requestAnimationFrame(drawFrame);
  }

  function startAnimation() {
    if (animationFrame) return;
    previousFrame = 0;
    renderer.resize();
    animationFrame = window.requestAnimationFrame(drawFrame);
  }

  function stopAnimation() {
    if (animationFrame) window.cancelAnimationFrame(animationFrame);
    animationFrame = 0;
    previousFrame = 0;
  }

  angleSlider.addEventListener("input", () => {
    simulation.angleDegrees = Number(angleSlider.value);
    angleValue.value = simulation.angleDegrees.toFixed(1);
    angleValue.textContent = simulation.angleDegrees.toFixed(1);
    renderer.draw(simulation);
  }, { signal });

  launchButton.addEventListener("click", () => {
    simulation.launch(Number(angleSlider.value));
    feedback.textContent = `Burn committed at ${simulation.angleDegrees.toFixed(1)}°. Tracking both objects at the same mission time…`;
    document.getElementById("interceptFeedback").dataset.result = "in-flight";
    metrics.hidden = true;
    startAnimation();
    updateReadouts();
  }, { signal });

  pauseButton.addEventListener("click", () => {
    simulation.togglePause();
    updateReadouts();
  }, { signal });

  resetButton.addEventListener("click", () => {
    resetFlight();
  }, { signal });

  document.querySelectorAll(".scenario-fields input").forEach((input) => {
    input.addEventListener("change", () => {
      const minimum = Number(input.min);
      const maximum = Number(input.max);
      const entered = Number(input.value);
      const value = Number.isFinite(entered) ? Math.min(maximum, Math.max(minimum, entered)) : Number(input.defaultValue);
      input.value = String(value);
      scenario = readScenarioInputs();
      simulation.scenario = scenario;
      renderer.scenario = scenario;
      resetFlight();
    }, { signal });
  });

  speedSelect.addEventListener("change", () => {
    simulation.speedMultiplier = Number(speedSelect.value);
  }, { signal });

  document.getElementById("interceptBackBtn").addEventListener("click", () => {
    window.showAppScreen("menuScreen");
  }, { signal });

  document.addEventListener("app:screen-changed", (event) => {
    if (event.detail.screenId === "interceptScreen") startAnimation();
    else stopAnimation();
  }, { signal });

  if ("ResizeObserver" in window) {
    const resizeObserver = new ResizeObserver(() => {
      renderer.resize();
      renderer.draw(simulation);
    });
    resizeObserver.observe(canvas);
    window.addEventListener("pagehide", () => resizeObserver.disconnect(), { once: true, signal });
  } else {
    window.addEventListener("resize", () => {
      renderer.resize();
      renderer.draw(simulation);
    }, { signal });
  }

  window.addEventListener("pagehide", () => {
    stopAnimation();
    control.abort();
  }, { once: true });

  renderer.resize();
  renderer.draw(simulation);
  updateReadouts();
}

function readScenarioInputs() {
  const value = (id) => Number(document.getElementById(id).value);
  return {
    rocket: {
      ...DEFAULT_SCENARIO.rocket,
      speed: value("rocketSpeedInput"),
      gravity: value("gravityInput")
    },
    planet: {
      ...DEFAULT_SCENARIO.planet,
      x0: value("planetXInput"),
      y0: value("planetYInput"),
      vx0: value("planetVxInput"),
      vy0: value("planetVyInput"),
      acceleration: value("planetAccelerationInput")
    },
    minAngle: DEFAULT_SCENARIO.minAngle,
    maxAngle: DEFAULT_SCENARIO.maxAngle,
    duration: DEFAULT_SCENARIO.duration
  };
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initializeInterception, { once: true });
} else {
  initializeInterception();
}