import { DEFAULT_SCENARIO, analyzeTrajectory, planetPosition, rocketPosition } from "./intercept-physics.mjs";
import { findBestInterceptionAngle } from "./intercept-solver.mjs";

export class InterceptSimulation {
  constructor(scenario = DEFAULT_SCENARIO) {
    this.scenario = scenario;
    this.angleDegrees = 45;
    this.elapsed = 0;
    this.speedMultiplier = 1;
    this.launched = false;
    this.running = false;
    this.paused = false;
    this.complete = false;
    this.analysis = null;
    this.solution = null;
  }

  launch(angleDegrees = this.angleDegrees) {
    if (this.running) return false;
    this.angleDegrees = angleDegrees;
    this.elapsed = 0;
    this.analysis = analyzeTrajectory(this.angleDegrees, this.scenario);
    this.solution = findBestInterceptionAngle(this.scenario);
    this.launched = true;
    this.paused = false;
    this.complete = false;
    this.running = true;
    this.advance(0);
    return true;
  }

  advance(realDeltaSeconds) {
    if (!this.launched || this.paused || this.elapsed >= this.scenario.duration) return;
    const nextTime = Math.min(this.scenario.duration, this.elapsed + Math.min(realDeltaSeconds, 0.1) * this.speedMultiplier);
    if (this.running) {
      const timeLimit = this.analysis.collisionTime ?? this.analysis.duration;
      if (nextTime >= timeLimit) {
        this.elapsed = timeLimit;
        this.running = false;
        this.complete = true;
        return;
      }
    }
    this.elapsed = nextTime;
  }

  togglePause() {
    if (!this.launched || this.complete) return;
    this.paused = !this.paused;
  }

  reset() {
    this.angleDegrees = 45;
    this.elapsed = 0;
    this.speedMultiplier = 1;
    this.launched = false;
    this.running = false;
    this.paused = false;
    this.complete = false;
    this.analysis = null;
    this.solution = null;
  }

  getRocketPosition(time = this.elapsed) {
    if (!this.launched) return { x: 0, y: 0 };
    const flightEnd = this.analysis?.collisionTime ?? this.analysis?.duration ?? time;
    return rocketPosition(this.angleDegrees, Math.min(time, flightEnd), this.scenario);
  }

  getPlanetPosition(time = this.elapsed) {
    return planetPosition(this.launched ? time : 0, this.scenario);
  }
}