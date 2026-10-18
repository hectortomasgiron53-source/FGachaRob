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
