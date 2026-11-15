# smg — explicación del proyecto

Juego/simulador de lanzamiento de cohetes hecho en **Godot 4.7** (Forward Plus, Jolt Physics). La idea central es que Godot **no calcula la física**: OpenRocket calcula el ascenso, GMAT propaga la órbita y Godot visualiza sus datos.

- **Fase atmosférica → OpenRocket 24.12** (Java). Vuela el ascenso desde la plataforma.
- **Fase orbital → NASA GMAT** (`GmatConsole`, por línea de comandos). Propaga la órbita.
- **Godot** dibuja el cohete, el cielo, la Tierra y el HUD a partir de esos datos.

Estado actual: el proyecto arranca directamente en la escena del cohete. El menú principal, los tres niveles y la interfaz de presupuesto/componentes se eliminaron el 14-11-2026.

---

## 1. Arquitectura

```
OpenRocket (Java, proceso aparte)          GMAT (GmatConsole, hilo aparte)
     │  líneas STEP/EVENT por stdout            │  fichero ReportFile
     ▼                                          ▼
  openrocket_sim.gd                          gmat_orbit.gd
     └──────────────┬───────────────────────────┘
              ▼
         rocket_launch.gd  ──►  rocket.gd, launch_camera.gd,
         (máquina de fases)      altitude_bar.gd, sky.gdshader
```

### Sistemas de coordenadas

| Sistema | Ejes |
|---|---|
| OpenRocket (mundo) | x este, y norte, z arriba |
| GMAT `EarthMJ2000Eq` | +Z polo norte, +X equinoccio vernal |
| Godot | +Y arriba, −Z adelante, +X derecha |

Conversión en ambos casos: `(x, y, z) → Vector3(x, z, -y)`. Los kilómetros orbitales se escalan (`orbit_units_per_km = 0.1`) para evitar el temblor de float32.

---

## 2. Archivos que existen hoy

| Archivo | Qué hace |
|---|---|
| `project.godot` | Escena principal `res://rocket_launch.tscn`. Sin autoloads. |
| `rocket_launch.tscn / .gd` | La escena del juego y su máquina de fases (plataforma, ascenso, éxito, órbita). |
| `rocket.gd` | Modelo visual del cohete, construido por código con cilindros, con forma de SLS: núcleo naranja, dos propulsores blancos, etapa superior, cápsula y torre de escape. Llamas, humo, luz, paracaídas y separación de etapas (`jettison()`). Es puramente cinemático. |
| `openrocket_sim.gd` | Lanza el puente Java, le manda `LAUNCH`, lee su salida en un hilo y reproduce los estados interpolados (`get_state()`). |
| `openrocket_bridge/OpenRocketBridge.java` (+ `.class`) | Programa Java sin interfaz que carga un `.ork`, ejecuta la simulación de OpenRocket y emite cada paso. |
| `rockets/simple_model_rocket.ork` | Diseño de OpenRocket que se vuela (un cohete de modelismo de 0,43 m; se dibuja 230 veces más grande). |
| `gmat_orbit.gd` | Escribe un script de GMAT, lo ejecuta y lee el informe. Órbita circular a 400 km, 28,5° de inclinación, 6 órbitas. |
| `launch_camera.gd` | Cámara que mantiene un ángulo de elevación constante hacia la punta del cohete. |
| `altitude_bar.gd` | Barra vertical del HUD con las capas de la atmósfera. |
| `sky.gdshader` | Cielo que pasa de azul a negro con estrellas según la capa. |
| `textures/` | `earth_8k.jpg`, `stars_sky.jpg`. |
| `rocket_ascent_model.json` | Especificación (ecuaciones E1–E26) de un modelo de ascenso 3D de masa variable y dos etapas, con un vehículo de ejemplo de 546 550 kg. Es documentación; el código solo usa su masa de despegue. |
| `docs/OpenRocket.md` | Especificación de OpenRocket para Godot. |
| `frontend/`, `server.py`, `catalog.json`, `mission_config.json`, `export_presets.cfg` | Lanzador local, catálogo de componentes y configuración de misión (ver sección 4.5). |
| `CLAUDE.md`, `prompt.md` | Instrucciones del proyecto y el encargo de la interfaz de presupuesto (ya no aplica). |
| `contexto.md` | Detalle técnico e historial de la sesión del 14-11-2026. |

### El puente de OpenRocket

Protocolo por stdout: `INFO`, `READY`, `STEP,t,px,py,pz,vx,vy,vz,ax,ay,az,thrust`, `EVENT,t,TIPO`, `DONE`, `ERROR`.

El catálogo y sus coeficientes son datos provisionales reconstruidos para esta integración, no una especificación histórica de piezas certificadas. GMAT conserva el propagador de órbita circular terrestre existente y recibe altitud e inclinación desde la misión. Solo **Around Earth** está habilitada para lanzamiento; las misiones lunar y marciana requieren un modelo de transferencia que el proyecto todavía no implementa.

---

## 3. Cómo se juega ahora

Espacio = lanzar · R = reiniciar · Escape = salir.

---

## 4. Todas las pantallas que ha tenido el proyecto

### 4.1 Escena de prueba inicial — `main.tscn` (eliminada)

La escena por defecto con la que empezó el proyecto: un cubo, una cámara y una luz direccional con sombras. Sin lógica.

### 4.2 Menú principal — `main_menu.tscn` + `main_menu.gd` (eliminado)

Un `Control` a pantalla completa con fondo opcional (`MainMenu.png`) y el título **"Project Ignition"**. Tenía cuatro páginas que se mostraban de una en una; Escape volvía a la principal.

1. **Página principal**: botones *Play*, *Settings* y *Credits*.
2. **Selección de nivel**: tres botones generados por código:
   - 1. *Around Earth* → abría `rocket_launch.tscn` (el único jugable).
   - 2. *To the Moon!* → sin escena.
   - 3. *Delivering to Mars!* → sin escena.
3. **Ajustes**: deslizador de volumen, desplegable de dificultad con su descripción, e interruptor de pantalla completa.
4. **Créditos**: texto editable desde el inspector.

Dependía del autoload `GameSettings` (`game_settings.gd`, eliminado): dificultades Easy / Normal / Hard / Extreme con multiplicadores `fuel` (1,5 / 1 / 0,75 / 0,5) y `hazard` (0,5 / 1 / 1,5 / 2), guardadas en `user://settings.cfg`. Ningún otro script llegó a leer esos multiplicadores.

### 4.3 Constructor del cohete (presupuesto) — `UI/builder_screen.tscn` (eliminado, nunca integrado)

Era un proyecto de Godot separado dentro de la carpeta `UI/` ("Rocket Odyssey"), hecho solo con nodos `Control` creados por código. Nunca se enlazó con el juego.

- **Paso 1 — elegir la punta**: cuadrícula 3×3, filas = forma (Cónica, Ojival, Von Kármán), columnas = material (Aluminio, Cerámica, Compuesto de carbono).
- **Paso 2 — elegir el fuselaje**: cuadrícula 3×3, filas = Tubo fino / Barril estándar / Barril ancho, columnas = Aluminio-litio / Titanio / Compuesto de carbono.
- Arriba, **barra de presupuesto** (30 M$ por defecto; ámbar, roja al pasarse). A la derecha, **panel de estadísticas** de la pieza y totales. Abajo, *Atrás*, pista de texto y *Siguiente / Confirmar*.
- Cada tarjeta mostraba material, coste, masa, resistencia y tolerancia térmica; se atenuaba si no cabía en el presupuesto.
- Al confirmar emitía `build_confirmed(build)`.

Le faltaban tres archivos que su propia documentación citaba (`ui_style.gd`, `part_grid.gd`, `stats_panel.gd`), así que no arrancaba tal cual. Todos los números eran provisionales.

Junto a ella había material de apoyo, también eliminado:
- `mission_component_efficiency_data/`: 14 propiedades, 14 componentes y 3 escenarios (órbita terrestre, alunizaje, aterrizaje en Marte) con la fórmula `eficiencia = 1 − Σ|necesario − elegido|·peso / 570`.
- `component_cost.md`: base de datos de costes con 14 categorías × 3 modelos (clase SLS Block 1, SLS Block 1B/2 y Starship V3).
- `INTEGRATION.md`, `PROMPT.md`, `HANDOFF_UI.md`: guías de integración.
- `Backenddesign/`: backend de presupuesto (`BudgetManager`, catálogo de 13 piezas, guardado, pruebas). Sin interfaz.

El plan que se empezó y se canceló era ampliar esta pantalla a los 14 componentes y hacer que cada elección cambiara la física real. De ese plan solo queda la opción `--vehicle` del puente.

### 4.4 Escena de lanzamiento — `rocket_launch.tscn` (la actual)

Una sola escena 3D que pasa por estas vistas:

1. **Plataforma**. Suelo verde con ruido, plataforma gris, cohete tipo SLS, cielo azul. HUD: telemetría arriba a la izquierda, barra de altitud a la izquierda, texto de estado abajo. Estado: "Starting OpenRocket..." y luego "Press SPACE to launch".
2. **Ascenso**. La cámara sigue al cohete con ángulo de elevación constante. Llamas en el núcleo y los propulsores, estela de humo. La telemetría muestra T+, altitud, velocidad y capa. El cielo cambia al cruzar las capas:
   - Troposfera (0–12 km): azul.
   - Estratosfera (12–50 km): azul oscuro, estrellas a medias.
   - Mesosfera (50–60 km): negro, estrellas completas.

   La trayectoria se dibuja comprimida (`altitude_scale = 0.08`); el HUD muestra los números reales.
3. **"Successful Launch"**. Rótulo grande centrado durante 4 s cuando OpenRocket termina (80 km).
4. **Órbita**. Se ocultan suelo, plataforma y barra; aparece la Tierra texturizada. El cohete (dibujado con 30 km de largo para que se vea) recorre la órbita de GMAT a 40× de velocidad. A los 3 s se separan el núcleo y los propulsores y la cámara se acerca a la etapa superior. El cohete se oscurece al entrar en la sombra de la Tierra. Telemetría: altitud, velocidad en km/s, masa (546 550 kg antes, 12 000 kg después), sol/sombra.

Limitación conocida: la órbita es siempre la misma (400 km circular); no depende de cómo haya ido el ascenso.

### 4.5 Lanzador web — `frontend/`

`python3 server.py` sirve el constructor local y el PWA exportado por Godot en `/godot`. La exportación conserva sus recursos y cabeceras COOP/COEP (`crossOriginIsolated` y `SharedArrayBuffer`). El constructor envía `POST /api/launch`; el servidor valida misión, dificultad, catálogo y presupuesto, guarda `mission_config.json` y lanza Godot nativo. El proceso nativo sigue siendo necesario para iniciar Java y `GmatConsole`.

En el tránsito a la Luna o Marte, Easy y Normal generan una ecuación de destino distinta en cada partida. Godot crea la sesión con `POST /api/transit/start`; el navegador obtiene los coeficientes con `GET /api/transit/state`, envía `angle_deg` a `POST /api/transit/answer` y Godot consulta `GET /api/transit/answer`. `POST /api/transit/result` publica el impacto o el error para mostrarlo en la web. Hard y Extreme no muestran el ejercicio.

### Exportar el reto a Web

1. Instala la plantilla de exportación correspondiente a Godot 4.7.2 y abre **Project > Export**.
2. Usa el preset `Web`. Su salida `../../../index.html` queda en la carpeta que el servidor publica como `/godot/` (`GODOT_WEB_DIR` puede cambiar esa carpeta).
3. Conserva activada la opción **Ensure Cross Origin Isolation** para que se envíen las cabeceras COOP/COEP requeridas por el PWA.
4. Sirve la salida mediante `python3 server.py`; no abras `index.html` con `file://`. La exportación debe estar bajo el mismo origen HTTP que la interfaz para que funcione el intercambio con el host.
5. Si el juego Web se integra en una página host mediante un `iframe` de `/godot/`, `transit.gd` anuncia `transit-start` con `JavaScriptBridge` y el host responde con `transit-answer` usando `postMessage`. El lanzamiento de escritorio usa la API local anterior y no requiere `JavaScriptBridge`.

El origen es el cohete `(0, 0)`. El ejercicio usa `y = tan(θ) · x` para el cohete y `y = ax² + bx + c` para el desplazamiento relativo del destino; el cohete vuela con el ángulo recibido y puede reintentarse si pasa fuera del radio del cuerpo.

La órbita GMAT recibe altitud e inclinación de la misión terrestre. Las misiones lunar y marciana se mantienen visibles en el catálogo, pero no se pueden lanzar hasta implementar propagación de transferencia; no se convierten silenciosamente en una órbita terrestre de 400 km.

---

## 5. Requisitos para ejecutar (escritorio)

- Godot 4.7.2.
- OpenRocket instalado en `~/OpenRocket` (con `jar/` y `jre/`) o en `$OPENROCKET_HOME`.
- GMAT en `~/GMAT` o en `$GMAT_HOME`. Se usa `GmatConsole`, no `gmatpy`, porque Arch trae un Python más nuevo que el 3.12 que GMAT necesita.
- Para recompilar el puente: `javac -cp ~/OpenRocket/jar/OpenRocket-24.12.jar OpenRocketBridge.java`.
