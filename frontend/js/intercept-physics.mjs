export const DEFAULT_SCENARIO = Object.freeze({
  rocket: Object.freeze({
    x0: 0,
    y0: 0,
    speed: 100,
    gravity: 9.81,
    radius: 4
  }),
  planet: Object.freeze({
    x0: 399.2,
    y0: 240,
    vx0: 4,
    vy0: 0,
    acceleration: 1.55,
    radius: 15
  }),
  minAngle: 5,
  maxAngle: 85,
  duration: 10
});

export function rocketPosition(angleDegrees, time, scenario = DEFAULT_SCENARIO) {
  const { x0, y0, speed, gravity } = scenario.rocket;
  const angle = angleDegrees * Math.PI / 180;
  return {
    x: x0 + speed * Math.cos(angle) * time,
    y: y0 + speed * Math.sin(angle) * time - 0.5 * gravity * time * time
  };
}

export function rocketVelocity(angleDegrees, time, scenario = DEFAULT_SCENARIO) {
  const { speed, gravity } = scenario.rocket;
  const angle = angleDegrees * Math.PI / 180;
  return {
    x: speed * Math.cos(angle),
    y: speed * Math.sin(angle) - gravity * time
  };
}

export function planetPosition(time, scenario = DEFAULT_SCENARIO) {
  const { x0, y0, vx0, vy0, acceleration } = scenario.planet;
  return {
    x: x0 + vx0 * time,
    y: y0 + vy0 * time + 0.5 * acceleration * time * time
  };
}

export function collisionRadius(scenario = DEFAULT_SCENARIO) {
  return scenario.rocket.radius + scenario.planet.radius;
}

export function rocketFlightDuration(angleDegrees, scenario = DEFAULT_SCENARIO) {
  const verticalSpeed = scenario.rocket.speed * Math.sin(angleDegrees * Math.PI / 180);
  if (verticalSpeed <= 0) return 0;
  return Math.min(scenario.duration, 2 * verticalSpeed / scenario.rocket.gravity);
}

function separationSquaredAt(angleDegrees, time, scenario) {
  const angle = angleDegrees * Math.PI / 180;
  const { x0, y0, speed, gravity } = scenario.rocket;
  const planet = scenario.planet;
  const rocketX = x0 + speed * Math.cos(angle) * time;
  const rocketY = y0 + speed * Math.sin(angle) * time - 0.5 * gravity * time * time;
  const planetX = planet.x0 + planet.vx0 * time;
  const planetY = planet.y0 + planet.vy0 * time + 0.5 * planet.acceleration * time * time;
  const dx = rocketX - planetX;
  const dy = rocketY - planetY;
  return dx * dx + dy * dy;
}

function refineCollisionTime(angleDegrees, low, high, radiusSquared, scenario) {
  for (let iteration = 0; iteration < 32; iteration += 1) {
    const middle = (low + high) * 0.5;
    if (separationSquaredAt(angleDegrees, middle, scenario) <= radiusSquared) high = middle;
    else low = middle;
  }
  return high;
}

function refineClosestTime(angleDegrees, low, high, scenario) {
  for (let iteration = 0; iteration < 28; iteration += 1) {
    const first = low + (high - low) / 3;
    const second = high - (high - low) / 3;
    if (separationSquaredAt(angleDegrees, first, scenario) <= separationSquaredAt(angleDegrees, second, scenario)) high = second;
    else low = first;
  }
  return (low + high) * 0.5;
}

export function analyzeTrajectory(angleDegrees, scenario = DEFAULT_SCENARIO, timeStep = 0.01, stopAtCollision = true) {
  const radius = collisionRadius(scenario);
  const radiusSquared = radius * radius;
  const endTime = rocketFlightDuration(angleDegrees, scenario);
  const step = Math.max(timeStep, 0.001);
  const angle = angleDegrees * Math.PI / 180;
  const relativeX0 = scenario.rocket.x0 - scenario.planet.x0;
  const relativeVelocityX = scenario.rocket.speed * Math.cos(angle) - scenario.planet.vx0;
  const horizontalClosestTime = Math.abs(relativeVelocityX) > 1e-12
    ? Math.max(0, Math.min(endTime, -relativeX0 / relativeVelocityX))
    : 0;
  const minimumHorizontal = Math.abs(relativeX0 + relativeVelocityX * horizontalClosestTime);
  let minimumSquared = separationSquaredAt(angleDegrees, 0, scenario);
  let closestTime = 0;
  let previousTime = 0;
  let previousSquared = minimumSquared;
  let collisionTime = previousSquared <= radiusSquared ? 0 : null;

  for (let time = Math.min(step, endTime); time <= endTime + 1e-9; time = Math.min(time + step, endTime)) {
    const distanceSquared = separationSquaredAt(angleDegrees, time, scenario);

    if (distanceSquared < minimumSquared) {
      minimumSquared = distanceSquared;
      closestTime = time;
    }
    if (collisionTime === null && previousSquared > radiusSquared && distanceSquared <= radiusSquared) {
      collisionTime = refineCollisionTime(angleDegrees, previousTime, time, radiusSquared, scenario);
      if (stopAtCollision) break;
    }
    previousTime = time;
    previousSquared = distanceSquared;
    if (time >= endTime) break;
  }

  const analyzedEnd = stopAtCollision ? (collisionTime ?? endTime) : endTime;
  if (analyzedEnd > 0) {
    const window = Math.max(step, (collisionTime === null ? endTime : collisionTime) * 0.02);
    closestTime = refineClosestTime(
      angleDegrees,
      Math.max(0, closestTime - window),
      Math.min(analyzedEnd, closestTime + window),
      scenario
    );
    minimumSquared = separationSquaredAt(angleDegrees, closestTime, scenario);
  }

  const closestRocket = rocketPosition(angleDegrees, closestTime, scenario);
  const closestPlanet = planetPosition(closestTime, scenario);
  const minimumDistance = Math.sqrt(minimumSquared);
  const status = collisionTime !== null
    ? "intercepted"
    : minimumHorizontal > radius
      ? "no-region"
      : "missed";
  let intercept = null;
  if (collisionTime !== null) {
    const rocket = rocketPosition(angleDegrees, collisionTime, scenario);
    const planet = planetPosition(collisionTime, scenario);
    intercept = { x: (rocket.x + planet.x) * 0.5, y: (rocket.y + planet.y) * 0.5 };
  }

  return {
    angleDegrees,
    status,
    duration: endTime,
    minimumDistance,
    minimumHorizontalDistance: minimumHorizontal,
    closestTime,
    closestRocket,
    closestPlanet,
    collisionTime,
    intercept,
    collisionRadius: radius
  };
}