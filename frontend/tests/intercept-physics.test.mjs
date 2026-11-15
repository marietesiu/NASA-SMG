import test from "node:test";
import assert from "node:assert/strict";
import {
  DEFAULT_SCENARIO,
  analyzeTrajectory,
  planetPosition,
  rocketPosition
} from "../js/intercept-physics.mjs";
import { findBestInterceptionAngle } from "../js/intercept-solver.mjs";
import { InterceptSimulation } from "../js/intercept-simulation.mjs";

test("rocket follows the configured ballistic equations", () => {
  const scenario = { ...DEFAULT_SCENARIO, rocket: { ...DEFAULT_SCENARIO.rocket, speed: 120, gravity: 3.71 } };
  const position = rocketPosition(45, 2, scenario);
  const expectedX = 120 * Math.cos(Math.PI / 4) * 2;
  const expectedY = 120 * Math.sin(Math.PI / 4) * 2 - 0.5 * 3.71 * 4;
  assert.ok(Math.abs(position.x - expectedX) < 1e-10);
  assert.ok(Math.abs(position.y - expectedY) < 1e-10);
});

test("planet follows its configurable parametric trajectory", () => {
  const scenario = { ...DEFAULT_SCENARIO, planet: { ...DEFAULT_SCENARIO.planet, x0: 420, y0: 100, vx0: 7, vy0: -2, acceleration: 0.8 } };
  const position = planetPosition(4, scenario);
  assert.equal(position.x, 420 + 7 * 4);
  assert.equal(position.y, 100 - 2 * 4 + 0.5 * 0.8 * 16);
});

test("collision is detected from simultaneous object positions", () => {
  const solution = findBestInterceptionAngle();
  const result = analyzeTrajectory(solution.angleDegrees);
  assert.equal(result.status, "intercepted");
  assert.ok(result.collisionTime > 0);
  const rocket = rocketPosition(solution.angleDegrees, result.collisionTime);
  const planet = planetPosition(result.collisionTime);
  const distance = Math.hypot(rocket.x - planet.x, rocket.y - planet.y);
  assert.ok(distance <= DEFAULT_SCENARIO.rocket.radius + DEFAULT_SCENARIO.planet.radius + 1e-6);
});

test("changing the angle changes the path and can miss the orbital region", () => {
  const defaultShot = analyzeTrajectory(45);
  const steepShot = analyzeTrajectory(85);
  assert.notEqual(rocketPosition(45, 3).y, rocketPosition(70, 3).y);
  assert.equal(defaultShot.status, "missed");
  assert.equal(steepShot.status, "no-region");
  assert.ok(defaultShot.minimumDistance < steepShot.minimumDistance);
});

test("angle solver finds a valid near-45 degree rendezvous", () => {
  const solution = findBestInterceptionAngle();
  assert.equal(solution.hasSolution, true);
  assert.equal(solution.result.status, "intercepted");
  assert.ok(Math.abs(solution.angleDegrees - 45) < 4);
  assert.equal(analyzeTrajectory(45).status, "missed");
  assert.ok(solution.result.minimumDistance < 0.1);
});

test("simulation pause, resume, and reset preserve the launch default", () => {
  const simulation = new InterceptSimulation();
  assert.equal(simulation.angleDegrees, 45);
  simulation.launch(45);
  simulation.advance(0.5);
  const pausedTime = simulation.elapsed;
  simulation.togglePause();
  simulation.advance(1);
  assert.equal(simulation.elapsed, pausedTime);
  simulation.togglePause();
  simulation.advance(0.25);
  assert.ok(simulation.elapsed > pausedTime);
  simulation.reset();
  assert.equal(simulation.angleDegrees, 45);
  assert.equal(simulation.launched, false);
  assert.equal(simulation.solution, null);
});