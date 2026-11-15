import {
  DEFAULT_SCENARIO,
  planetPosition,
  rocketFlightDuration,
  rocketPosition,
  rocketVelocity
} from "./intercept-physics.mjs";

const WORLD = { minX: -70, maxX: 1050, minY: -80, maxY: 550 };

export class InterceptRenderer {
  constructor(canvas, scenario = DEFAULT_SCENARIO) {
    this.canvas = canvas;
    this.context = canvas.getContext("2d");
    this.scenario = scenario;
    this.width = 0;
    this.height = 0;
    this.pixelRatio = 1;
    this.stars = Array.from({ length: 64 }, (_, index) => ({
      x: ((index * 127 + 31) % 997) / 997,
      y: ((index * 263 + 89) % 991) / 991,
      radius: 0.55 + (index % 4) * 0.22,
      alpha: 0.18 + (index % 5) * 0.1
    }));
  }

  resize() {
    const bounds = this.canvas.getBoundingClientRect();
    if (!bounds.width || !bounds.height) return;
    this.pixelRatio = Math.min(window.devicePixelRatio || 1, 2);
    this.width = bounds.width;
    this.height = bounds.height;
    this.canvas.width = Math.round(this.width * this.pixelRatio);
    this.canvas.height = Math.round(this.height * this.pixelRatio);
    this.context.setTransform(this.pixelRatio, 0, 0, this.pixelRatio, 0, 0);
  }

  draw(simulation) {
    if (!this.width || !this.height) this.resize();
    if (!this.width || !this.height) return;
    const context = this.context;
    const scale = Math.min(this.width / (WORLD.maxX - WORLD.minX), this.height / (WORLD.maxY - WORLD.minY));
    const left = (this.width - (WORLD.maxX - WORLD.minX) * scale) * 0.5;
    const top = (this.height - (WORLD.maxY - WORLD.minY) * scale) * 0.5;
    const toX = (x) => left + (x - WORLD.minX) * scale;
    const toY = (y) => top + (WORLD.maxY - y) * scale;

    context.clearRect(0, 0, this.width, this.height);
    const background = context.createLinearGradient(0, 0, this.width, this.height);
    background.addColorStop(0, "#071726");
    background.addColorStop(0.55, "#07111d");
    background.addColorStop(1, "#030a12");
    context.fillStyle = background;
    context.fillRect(0, 0, this.width, this.height);
    this.drawStars(context);
    this.drawGrid(context, toX, toY, scale);
    this.drawPlanetTrajectory(context, toX, toY, scale);
    this.drawRocketTrajectory(context, simulation, toX, toY, scale);
    this.drawLaunchPoint(context, toX, toY);
    this.drawPlanet(context, simulation.getPlanetPosition(), toX, toY, scale);
    if (simulation.launched) this.drawRocket(context, simulation, toX, toY, scale);
    if (simulation.complete && simulation.analysis?.intercept) {
      this.drawInterceptMarker(context, simulation.analysis.intercept, toX, toY);
    }
  }

  drawStars(context) {
    for (const star of this.stars) {
      context.beginPath();
      context.fillStyle = `rgba(177, 220, 244, ${star.alpha})`;
      context.arc(star.x * this.width, star.y * this.height, star.radius, 0, Math.PI * 2);
      context.fill();
    }
  }

  drawGrid(context, toX, toY, scale) {
    context.save();
    context.lineWidth = 1;
    context.strokeStyle = "rgba(82, 147, 177, 0.11)";
    for (let x = 0; x <= 1000; x += 100) {
      context.beginPath();
      context.moveTo(toX(x), toY(WORLD.minY));
      context.lineTo(toX(x), toY(WORLD.maxY));
      context.stroke();
    }
    for (let y = 0; y <= 500; y += 100) {
      context.beginPath();
      context.moveTo(toX(WORLD.minX), toY(y));
      context.lineTo(toX(WORLD.maxX), toY(y));
      context.stroke();
      context.fillStyle = "rgba(153, 183, 199, 0.55)";
      context.font = "10px 'Satoshi', sans-serif";
      context.fillText(`${y}`, toX(WORLD.minX) + 26, toY(y) - 5);
    }
    context.strokeStyle = "rgba(116, 190, 214, 0.34)";
    context.beginPath();
    context.moveTo(toX(WORLD.minX), toY(0));
    context.lineTo(toX(WORLD.maxX), toY(0));
    context.stroke();
    context.beginPath();
    context.moveTo(toX(0), toY(WORLD.minY));
    context.lineTo(toX(0), toY(WORLD.maxY));
    context.stroke();
    context.restore();
  }

  drawPlanetTrajectory(context, toX, toY, scale) {
    context.save();
    context.beginPath();
    for (let time = 0; time <= this.scenario.duration; time += 0.08) {
      const position = planetPosition(time, this.scenario);
      if (time === 0) context.moveTo(toX(position.x), toY(position.y));
      else context.lineTo(toX(position.x), toY(position.y));
    }
    context.setLineDash([2, 7]);
    context.lineWidth = 2;
    context.strokeStyle = "rgba(74, 205, 230, 0.67)";
    context.stroke();
    const orbitStart = planetPosition(0, this.scenario);
    context.setLineDash([]);
    context.beginPath();
    context.arc(toX(orbitStart.x), toY(orbitStart.y), Math.max(2, 4 * scale), 0, Math.PI * 2);
    context.fillStyle = "#70e1ee";
    context.fill();
    context.restore();
  }

  drawRocketTrajectory(context, simulation, toX, toY) {
    const duration = rocketFlightDuration(simulation.angleDegrees, this.scenario);
    const angle = simulation.angleDegrees;
    context.save();
    context.beginPath();
    for (let time = 0; time <= duration; time += 0.06) {
      const position = rocketPosition(angle, time, this.scenario);
      if (position.y < 0 && time > 0) break;
      if (time === 0) context.moveTo(toX(position.x), toY(position.y));
      else context.lineTo(toX(position.x), toY(position.y));
    }
    context.setLineDash([8, 7]);
    context.lineWidth = 2;
    context.strokeStyle = "rgba(255, 170, 94, 0.78)";
    context.stroke();
    context.restore();

    if (simulation.launched) {
      const position = simulation.getRocketPosition();
      context.save();
      context.beginPath();
      context.moveTo(toX(0), toY(0));
      context.lineTo(toX(position.x), toY(position.y));
      context.setLineDash([]);
      context.lineWidth = 3;
      context.strokeStyle = "#fff0d6";
      context.shadowBlur = 12;
      context.shadowColor = "rgba(255, 240, 214, 0.4)";
      context.stroke();
      context.restore();
    }
  }

  drawLaunchPoint(context, toX, toY) {
    const x = toX(0);
    const y = toY(0);
    context.save();
    context.beginPath();
    context.arc(x, y, 5, 0, Math.PI * 2);
    context.fillStyle = "#fff0d6";
    context.fill();
    context.strokeStyle = "rgba(255, 180, 95, 0.55)";
    context.lineWidth = 7;
    context.stroke();
    context.restore();
  }

  drawPlanet(context, position, toX, toY, scale) {
    const x = toX(position.x);
    const y = toY(position.y);
    const radius = Math.max(8, this.scenario.planet.radius * scale);
    context.save();
    context.beginPath();
    context.arc(x, y, radius + 7, 0, Math.PI * 2);
    context.fillStyle = "rgba(55, 193, 221, 0.08)";
    context.fill();
    const surface = context.createRadialGradient(x - radius * 0.4, y - radius * 0.45, radius * 0.1, x, y, radius);
    surface.addColorStop(0, "#bdfff2");
    surface.addColorStop(0.35, "#54cad4");
    surface.addColorStop(0.75, "#19738f");
    surface.addColorStop(1, "#0a334e");
    context.beginPath();
    context.arc(x, y, radius, 0, Math.PI * 2);
    context.fillStyle = surface;
    context.fill();
    context.strokeStyle = "rgba(139, 246, 232, 0.8)";
    context.lineWidth = 1.2;
    context.stroke();
    context.restore();
  }

  drawRocket(context, simulation, toX, toY, scale) {
    const position = simulation.getRocketPosition();
    const rocketTime = Math.min(simulation.elapsed, simulation.analysis?.collisionTime ?? simulation.analysis?.duration ?? simulation.elapsed);
    const velocity = rocketVelocity(simulation.angleDegrees, rocketTime, this.scenario);
    const direction = Math.atan2(velocity.y, velocity.x);
    const x = toX(position.x);
    const y = toY(position.y);
    context.save();
    context.translate(x, y);
    context.rotate(-direction);
    context.shadowBlur = 15;
    context.shadowColor = "rgba(255, 178, 96, 0.8)";
    context.beginPath();
    context.moveTo(13, 0);
    context.lineTo(-8, -5);
    context.lineTo(-5, 0);
    context.lineTo(-8, 5);
    context.closePath();
    context.fillStyle = "#fff0d6";
    context.fill();
    context.beginPath();
    context.moveTo(-7, -3);
    context.lineTo(-14 - Math.min(7, scale * 5), 0);
    context.lineTo(-7, 3);
    context.fillStyle = "#ff8b45";
    context.fill();
    context.restore();
  }

  drawInterceptMarker(context, position, toX, toY) {
    const x = toX(position.x);
    const y = toY(position.y);
    context.save();
    context.strokeStyle = "#b5ffd8";
    context.lineWidth = 2;
    context.shadowBlur = 16;
    context.shadowColor = "rgba(124, 230, 177, 0.8)";
    context.beginPath();
    context.arc(x, y, 18, 0, Math.PI * 2);
    context.stroke();
    context.beginPath();
    context.moveTo(x - 25, y);
    context.lineTo(x + 25, y);
    context.moveTo(x, y - 25);
    context.lineTo(x, y + 25);
    context.stroke();
    context.restore();
  }
}