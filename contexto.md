# Contexto de la sesión (14-11-2026)

Todo lo que sé del proyecto y de lo que se hizo en esta sesión, para poder retomarlo sin releer nada. La descripción general del proyecto y de cada pantalla está en `project.md`; aquí va el detalle técnico y el historial.

## 1. Entorno

- Proyecto: antes en `/home/mario/smg`, ahora en `/home/mario/Downloads/Directory/Godot/smg` (se movió durante la sesión; ahora es un repositorio git con un commit, "Minor fixes").
- Godot: `/home/mario/Downloads/Godot_v4.7.2-stable_linux.x86_64` (no está en el PATH).
- OpenRocket: `/home/mario/OpenRocket` — solo el jar `jar/OpenRocket-24.12.jar` y un JRE 17; **no hay código fuente** (la ruta de fuentes de `CLAUDE.md` no existe). Para ver la API usé `javap -cp <jar> info.openrocket.core.<Clase>`.
- GMAT: `/home/mario/GMAT`, ejecutable `bin/GmatConsole`, con `LD_LIBRARY_PATH=/home/mario/GMAT/bin`.
- Java del sistema: OpenJDK 17. Python 3 disponible.
- `.claude/settings.local.json` prohíbe editar `OpenRocket/` y `GMAT/`.
- Arch Linux, sin `godot` en el PATH.

## 2. Qué se pidió y qué pasó

1. **Encargo inicial** (`prompt.md`): crear la interfaz del Nivel 1 con el sistema de la carpeta `UI/`, enlazar los componentes con la física real, que los fallos salgan de la física sin codificarlos a mano, avisos en órbita con explicación de tres frases para lo no crítico, y que lo crítico impida llegar a órbita.
2. Leí todo el proyecto y la carpeta `UI/`, diseñé el sistema y amplié el puente de OpenRocket.
3. **Cambio de planes**: se pidió borrar todo lo que no fuera la simulación del cohete.
4. Se pidió este archivo y `project.md`.

## 3. Estado del código ahora

- `project.godot`: escena principal `res://rocket_launch.tscn`; se quitó el autoload `GameSettings`.
- `rocket_launch.gd`: se quitó `menu_scene`; Escape llama a `get_tree().quit()`.
- Enviados a la papelera con `gio trash` (recuperables): `main_menu.gd/.tscn`, `main.tscn`, `game_settings.gd`, carpeta `UI/`. `Backenddesign/` ya no estaba cuando fui a quitarla.
- Comprobado: `--headless --import` sin errores y la escena arranca ("OpenRocket design: A simple model rocket. Camera elevation angle: 16.7 deg").
- Aparecieron durante la sesión, no hechos por mí y no revisados a fondo: `frontend/`, `server.py`, `docs/web_launcher.md`, `export_presets.cfg` (lanzador web).

## 4. El puente de OpenRocket: lo que añadí

Archivo `openrocket_bridge/OpenRocketBridge.java`, compilado. Las opciones antiguas siguen igual. Nueva opción `--vehicle clave=valor,...` con dos clases internas, `Vehicle` y `VehicleFlight`.

Claves (SI): `dry_mass`, `propellant`, `thrust_sl`, `thrust_vac`, `isp_vac`, `ref_area`, `length`, `cg_dry`, `cg_prop` (0..1 desde la punta), `static_margin` (calibres, + = estable), `gimbal_max` (grados), `q_alpha_limit` (Pa·rad), `tank_limit` (Pa), `ullage` (Pa), `prop_density`, `column` (m), `heat_limit` (W/m²), `nose_radius`, `wind_ground`, `wind_jet` (m/s).

Cómo funciona (todo mediante los *listeners* de OpenRocket, dentro de su integrador RK4):
- **Masa** (`postMassCalculation`): seca + propelente restante. OpenRocket llama dos veces (estructura y motor); distingo la del motor comparando con la masa de estructura del modelo y devuelvo `RigidBody.EMPTY`.
- **Empuje** (`postSimpleThrustCalculation`): `T = T_vac − (T_vac − T_sl)·p/p0`; el propelente baja a `T_vac/(Isp·g0)`; al agotarse, MECO.
- **Aerodinámica** (`postAerodynamicCalculation`): coeficientes de OpenRocket para la forma del `.ork`, escalados por área real / área del modelo. El centro de presiones se fija a `static_margin` calibres del centro de masas de despegue.
- **Viento** (`postWindModel`): `wind_ground` en el suelo y un chorro gaussiano centrado en 11 km (ancho 4 km).
- **Control de actitud** (`postAccelerationCalculation`): ley PD que mantiene la punta vertical, limitada por `empuje·sin(gimbal_max)·brazo/inercia`.
- **Fallos** (`postStep`), en este orden: `TANK_RUPTURE` (ullage + ρ·(T/m)·columna > límite), `STRUCTURAL_BREAKUP` (q·|α| > límite), `NOSE_BURNTHROUGH` (flujo de calor tipo Sutton-Graves > límite), `NO_LIFTOFF` (a los 8 s sigue en el suelo), `LOST_CONTROL` (cae o se inclina más de 75°). Tras un fallo se corta el empuje y la simulación acaba 6 s después.
- Salida nueva: `FAIL,t,CÓDIGO,valor,límite`, `MECO,t,alt,vx,vy,vz,masa`, `SUMMARY,max_q=...` con picos y límites.
- Truco de escalas: los ángulos son reales, las longitudes a lo largo del cuerpo son las del modelo, así que la inercia lleva un factor de escala de longitud.

### Resultados de las pruebas por línea de comandos

Vehículo de referencia: `dry_mass=152840, propellant=395700, thrust_sl=7592000, thrust_vac=8200000, isp_vac=311, ref_area=10.52, length=70, cg_dry=0.5, cg_prop=0.6, static_margin=1.2, gimbal_max=1.35, q_alpha_limit=5000, tank_limit=620000, ullage=300000, prop_density=1140, column=5, heat_limit=100000, nose_radius=1, wind_ground=5, wind_jet=40`.

| Caso | Resultado |
|---|---|
| Referencia | MECO a 147,2 s, 111 km, 2343 m/s vertical; q máx 32,6 kPa; q·α máx 2063; tanque máx 6,06 bar; aceleración máx 53,6 m/s² |
| margen −1,2, cardán 0,15° | Rotura estructural a 59 s |
| margen −1,2, cardán 0,45° | Llega a MECO |
| margen +1,2, cardán 0,05° | Llega, con 8,4° de inclinación máxima |
| margen +2, cardán 0° | Pérdida de control a 116 s |
| `tank_limit=500000` | Rotura de tanque a 117 s |
| empuje 5,6 / 6,1 MN | MECO a 198 s, 98 km, 1850 m/s |
| empuje 5,2 / 5,7 MN | No despega (T/W 0,99) |
| `wind_jet=80` | Llega, q·α 4167 (cerca del límite), 1753 m/s |

Cada simulación tarda unos 5 s y produce unas 3000 líneas `STEP`.

**No verificado**: el convenio de signo del viento (el cohete derivó hacia +x con viento definido hacia −x) y la prueba de GMAT (ver abajo).

## 5. Diseño que quedó sin implementar

Por si se retoma la idea de componentes → física:

- 14 categorías × 3 modelos (M1 clase SLS Block 1, M2 SLS Block 1B/2, M3 Starship V3), con masa y coste reales de `component_cost.md`. Totales en dólares de 2026: M1 ≈ 38,3 M$, M2 ≈ 54,8 M$, M3 ≈ 72,0 M$. Masas: ≈ 12,7 t / 19,0 t / 27,2 t (las bombas no traían masa; había que suponerla).
- Valores por modelo a partir de la base de la categoría `b`: propiedades que aporta (b > 5): M1 = b−2, M2 = b, M3 = min(10, b+1); masa y coste: M1 = b+1, M2 = b, M3 = b−1.
- Puntuación del vehículo por propiedad = media de los componentes que la aportan.
- Vehículo base tomado de `rocket_ascent_model.json`: etapa 1 seca 25,6 t con 395,7 t de propelente, 8,2 MN en vacío, Isp 311 s; etapa 2 seca 4 t con 111,5 t, 934 kN, Isp 348 s; carga 8 t.
- Enlace previsto: masa → kg reales; empuje e Isp → multiplicadores; estabilidad → margen estático; control de actitud → cardán máximo y error de apuntado en la inserción; integridad estructural → límite q·α; contención de presión → presión de rotura; protección térmica → límite de flujo; aislamiento criogénico → evaporación de propelente.
- Órbita: tras el MECO, calcular con vis-viva la inserción según el delta-v que quede y pasar el estado cartesiano a GMAT con arrastre (`JacchiaRoberts`) y condición de parada por altitud, para que una inserción insuficiente reentre de verdad. Margen estimado con 8 t de carga: unos 1,4 km/s de sobra, demasiado holgado; habría que subir la carga a unas 13,5 t.
- La prueba de GMAT con esos scripts **no llegó a ejecutarse**: `GmatConsole` cambia su directorio de trabajo a `GMAT/bin`, así que hay que pasarle la ruta absoluta del script.

## 6. Datos del sistema de eficiencia (carpeta eliminada)

- Propiedades (14) y peso: mass 5, structural_integrity 5, thermal_protection 4, cryo_insulation 3, pressure_containment 5, payload_capacity 5, payload_volume 3, aerodynamic_stability 3, attitude_control 4, specific_impulse 4, thrust_output 4, unit_cost 4, deep_space_endurance 3, edl_survivability 5. Suma 57, hueco máximo 570.
- Valores necesarios para órbita terrestre, en ese orden: 8, 5, 3, 5, 10, 8, 5, 8, 8, 8, 5, 8, 3, 0.
- Componentes (14): nose_cone_tip, frustum, bulk_plates, payload_adapter, frames_skirt, fairings, control_fins, thrust_structures, passive_fins, oxidizer_tanks, fuel_tanks, heat_exchanger, bipropellant_valves_injector, pumps_turbopumps.
- Fórmula: `eficiencia = 1 − Σ|necesario − elegido|·peso / 570`. Comprobación: órbita terrestre / bulk_plates = hueco 113, eficiencia 0,8018.

## 7. Preferencias del usuario

- No añadir decoración ni elementos puramente visuales que no se hayan pedido (memoria guardada).
- Respuestas cortas y directas; escribe en español.

## 8. Pendiente / dudas abiertas

- `prompt.md` describe una tarea que ya no aplica; sigue en el proyecto.
- `CLAUDE.md` apunta a rutas que ya no existen (fuentes de OpenRocket, `docs/openrocket_godot_specification.md`).
- La opción `--vehicle` no está conectada a `openrocket_sim.gd`.
- La órbita de GMAT es fija y no recibe el estado final del ascenso, aunque `CLAUDE.md` dice que debería.
- El lanzador web no puede ejecutar OpenRocket ni GMAT en el navegador.
