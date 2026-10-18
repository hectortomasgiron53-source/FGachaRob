# Fútbol Gacha: Bloque 1 (fases 0, 1 y 2)

Partido de práctica 3v3 jugable de principio a fin: campo generado por código, balón con física del servidor,
control del jugador, reglas (cuenta atrás, goles, gol de oro, final) y HUD mínimo. Los rivales y tus compañeros
son muñecos quietos hasta la Fase 3 (bots).

## Opción A: con Rojo (recomendado, es lo que pide la Fase 0)
1. Instala Rojo (extensión de VS Code + plugin de Rojo en Studio).
2. Abre esta carpeta en VS Code y ejecuta `rojo serve`.
3. En Studio: crea un lugar nuevo (plantilla Baseplate, que ya trae un SpawnLocation) y pulsa Connect en el plugin de Rojo.
4. Pulsa Play.

## Opción B: copiando a mano en Studio
Crea cada archivo como el tipo de objeto indicado, con ESE nombre exacto, y pega dentro el código.

| Archivo | Dónde va en Studio | Tipo |
| --- | --- | --- |
| src/shared/Config/Balance.lua | ReplicatedStorage > Shared > Config > Balance | ModuleScript |
| src/shared/Config/Characters.lua | ReplicatedStorage > Shared > Config > Characters | ModuleScript |
| src/shared/Locale/Strings.lua | ReplicatedStorage > Shared > Locale > Strings | ModuleScript |
| src/shared/Util/MathUtil.lua | ReplicatedStorage > Shared > Util > MathUtil | ModuleScript |
| src/shared/Remotes.lua | ReplicatedStorage > Shared > Remotes | ModuleScript |
| src/shared/Types.lua | ReplicatedStorage > Shared > Types | ModuleScript |
| src/server/Boot.server.lua | ServerScriptService > Boot | Script |
| src/server/Services/RemoteValidator.lua | ServerScriptService > Services > RemoteValidator | ModuleScript |
| src/server/Services/ArenaBuilder.lua | ServerScriptService > Services > ArenaBuilder | ModuleScript |
| src/server/Services/Ball.lua | ServerScriptService > Services > Ball | ModuleScript |
| src/server/Services/Match.lua | ServerScriptService > Services > Match | ModuleScript |
| src/server/Services/MatchService.lua | ServerScriptService > Services > MatchService | ModuleScript |
| src/server/Services/InputService.lua | ServerScriptService > Services > InputService | ModuleScript |
| src/server/Services/DebugService.lua | ServerScriptService > Services > DebugService | ModuleScript |
| src/client/Client.client.lua | StarterPlayer > StarterPlayerScripts > Client | LocalScript |
| src/client/Controllers/MatchController.lua | StarterPlayerScripts > Controllers > MatchController | ModuleScript |
| src/client/Controllers/CameraController.lua | StarterPlayerScripts > Controllers > CameraController | ModuleScript |
| src/client/Controllers/InputController.lua | StarterPlayerScripts > Controllers > InputController | ModuleScript |
| src/client/Controllers/UIController.lua | StarterPlayerScripts > Controllers > UIController | ModuleScript |

Las carpetas (Shared, Config, Locale, Util, Services, Controllers) son de tipo Folder.
Crea los Folder y mueve los ModuleScript dentro. No hace falta crear la carpeta Remotes: el servidor la crea sola.

## Cómo probar
1. Pulsa Play (F5) y luego el botón verde "Jugar partido de práctica".
2. Controles: mover con WASD / joystick; Shift sprint; click derecho (mantener) gira la cámara.
   - Siempre: E pase; F tiro (mantén para cargar).
   - Con balón: R croqueta (salto lateral); T sombrero.
   - Sin balón: Q entrada; C segada.
   - Mando: X pase, B tiro, L2 sprint, L1 croqueta, Y entrada, R1 sombrero (con balón) / segada (sin balón).
3. Atajos solo de Studio: Y gol azul, U gol rojo, I deja 5 segundos, O termina el partido, P balón al centro.
4. Para probar con latencia: Studio > File > Studio Settings > Network > Incoming Replication Lag (0.15 s).

## Qué falta del Bloque 1
- Pruebas automáticas con Jest-Lua o TestEZ, y Wally para instalarlas.
- Modo de simulación bot contra bot (necesita la IA de la Fase 3).
- Animaciones de pase, tiro, entrada y celebración, y una guía de arte.
- Mover el campo a ServerStorage como modelo propio (aquí se genera por código en ArenaBuilder).


## Lobby / Spawn

El servicio `SpawnService` genera el lobby de estadio. Si usas la plantilla Baseplate de Roblox, el servicio elimina la pieza predeterminada `Baseplate` para evitar superficies coplanares (z-fighting/parpadeo). El lobby se genera de nuevo al iniciar el servidor.


## Archivos nuevos (v0.22)
| Archivo | Dónde va en Studio | Tipo |
| --- | --- | --- |
| src/server/Services/CollisionSetup.lua | ServerScriptService > Services > CollisionSetup | ModuleScript |
| src/client/Controllers/BallVisual.lua | StarterPlayerScripts > Controllers > BallVisual | ModuleScript |

## Campo de exhibición (patio de juegos)
Al oeste del lobby hay un campo siempre generado con una puerta (lado que mira al lobby). Al entrar, juegas solo con el balón
(mismos controles que en partido, sin goles ni marcador); si el balón se queda dentro de una portería, vuelve al centro.
Se sale por la misma puerta. Ajustes en `Balance.Playground` y `Balance.Field.GateWidth`.

## v0.29
- Partido de práctica 4v4: 3 de campo + 1 portero por equipo (slot 4, `Balance.Match.GoalkeeperSlot`). El portero se mueve
  por su línea de gol, sigue el balón y para tiros (ajustes en `Balance.Goalkeeper`).
- Público del lobby: personajes R15 de Roblox, cada uno con su estilo, sentados en asientos de estadio.
- Guía de controles por secciones (abajo a la derecha); la sección que no aplica se atenúa.

## v0.37: sonidos y animaciones
- Archivo nuevo: `src/client/Controllers/FxController.lua` -> StarterPlayerScripts > Controllers > FxController (ModuleScript).
- Sonidos: sube los .mp3 de `sonidos.zip` a Roblox y pega los IDs en `Balance.Sounds`.
- Animaciones por codigo (sin assets) para R15: pase, tiro, tiro alto, sombrero, croqueta, entrada, segada,
  estirada / salto / blocaje / despeje del portero y celebracion de gol.

## v0.38 - v0.40: configuracion de sonido
- Scripts nuevos (ModuleScript en StarterPlayerScripts > Controllers): `AudioSettings` y `SettingsController`.
- Boton de engranaje arriba a la derecha: volumen general, efectos y publico (solo para ese jugador).
- Sonidos: 10 .mp3 en `sonidos` (incluye tackle.mp3); sus IDs van en `Balance.Sounds`.

## V0.32: sorteo de saque con moneda
- Script nuevo: `src/client/Controllers/CoinTossController.lua` -> StarterPlayerScripts > Controllers > CoinTossController (ModuleScript).
- Antes de cada partido: el equipo AZUL pide cara o cruz (en el modo de un jugador eliges tú con los botones; si no eliges en
  12 s, se elige al azar). La moneda sale despedida desde una mesa junto al centro del campo, gira en el aire y cae en la mesa
  mostrando el lado que ha salido. Quien gana elige SACAR o CEDER EL SAQUE (si gana la máquina, decide ella). Después, la
  cuenta atrás de siempre.
- El resultado lo decide el servidor (`Match.lua`, fase "CoinToss"); la mesa, la moneda y la interfaz son solo del cliente.
- Ajustes en `Balance.CoinToss` (tiempos, posición de la mesa; `Enabled = false` lo quita).
- Sonidos (opcionales): `sonidos/coin_flip.mp3` y `sonidos/coin_land.mp3` -> IDs en `Balance.Sounds.CoinFlip` y `Balance.Sounds.CoinLand`.

## V0.33: saque de centro reglamentario
- El delantero del equipo que saca pasa SIEMPRE hacia atrás, solo y a un compañero al azar (los otros dos de campo
  o el portero). Mientras espera el pase (0,7 s tras el silbato) no puede moverse ni hacer acciones.
- Mientras viaja el pase, solo el compañero elegido puede controlar el balón.
- Los rivales no pueden entrar en el círculo central hasta 2 s después del pase (una barrera invisible los saca).
- Ajustes en `Balance.Kickoff`.

## V0.34: bots de campo (nivel 1)
- Script nuevo: `src/server/Services/BotBrain.lua` -> ServerScriptService > Services > BotBrain (ModuleScript).
- Los jugadores de campo de la máquina ya juegan: el más cercano va a por el balón (o presiona y hace entradas),
  el resto se coloca según el balón (suben al atacar, bajan al defender, sin amontonarse). Con balón conducen,
  tiran si están cerca y con ángulo, pasan si les presionan y a veces intentan una croqueta.
- Usan las mismas acciones y reglas que un humano. Los porteros siguen igual.
- Ajustes en `Balance.Bots` (`Enabled = false` los vuelve a dejar quietos).

## V0.35: bots nivel 2 + balón más pegado + robar más fácil
- Bots: cada equipo reparte papeles (presión, cobertura, marcaje, apoyos que buscan hueco con línea de pase libre).
  Pases medidos y al hueco, tiros al palo contrario al portero (o vaselina si está adelantado). Giros, frenadas
  y ritmos progresivos (trotan si no hay prisa, se perfilan antes de golpear). Ajustes en `Balance.Bots`.
- Balón al conducir: más cerca del pie (`DribbleDistance` 2.6) y sin adelanto en los bots ni en tu pantalla.
- Robar: la entrada vale al jugador o al balón; robo por contacto al pegarte al balón (`ContactStealRange/Rate`);
  con balón se corre un 10 % menos (`DribbleSpeedFactor`).
