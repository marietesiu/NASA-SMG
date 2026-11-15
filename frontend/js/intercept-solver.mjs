import { DEFAULT_SCENARIO, analyzeTrajectory } from "./intercept-physics.mjs";

function goldenSectionMinimum(objective, low, high, iterations = 28) {
  const ratio = (Math.sqrt(5) - 1) / 2;
  let left = high - ratio * (high - low);
  let right = low + ratio * (high - low);
  let leftValue = objective(left);
  let rightValue = objective(right);

  for (let index = 0; index < iterations; index += 1) {
    if (leftValue <= rightValue) {
      high = right;
      right = left;
      rightValue = leftValue;
      left = high - ratio * (high - low);
      leftValue = objective(left);
    } else {
      low = left;
      left = right;
      leftValue = rightValue;
      right = low + ratio * (high - low);
      rightValue = objective(right);
    }
  }
  return (low + high) * 0.5;
}

export function findBestInterceptionAngle(scenario = DEFAULT_SCENARIO, angleStep = 0.25) {
  const count = Math.ceil((scenario.maxAngle - scenario.minAngle) / angleStep);
  let bestAngle = scenario.minAngle;
  let bestDistance = Infinity;

  for (let index = 0; index <= count; index += 1) {
    const angle = Math.min(scenario.minAngle + index * angleStep, scenario.maxAngle);
    const result = analyzeTrajectory(angle, scenario, 0.025, false);
    if (result.minimumDistance < bestDistance) {
      bestAngle = angle;
      bestDistance = result.minimumDistance;
    }
  }

  const low = Math.max(scenario.minAngle, bestAngle - angleStep);
  const high = Math.min(scenario.maxAngle, bestAngle + angleStep);
  const refinedAngle = goldenSectionMinimum(
    (angle) => analyzeTrajectory(angle, scenario, 0.01, false).minimumDistance,
    low,
    high
  );
  const result = analyzeTrajectory(refinedAngle, scenario, 0.005, false);

  return {
    angleDegrees: refinedAngle,
    result,
    hasSolution: result.status === "intercepted"
  };
}