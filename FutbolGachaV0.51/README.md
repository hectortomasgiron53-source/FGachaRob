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

## V0.36: formación y más pases
- Los bots juegan en formación de fútbol sala (pívot, ala y cierre) que se mueve en bloque con el balón.
  Solo UNO va al balón; los demás mantienen su puesto (en defensa: línea por detrás del balón y uno más atrás,
  marcando al rival que entre en su zona). Ajustes en `Balance.Bots.Shape`.
- Tras un pase, va a por el balón el receptor (al punto donde lo intercepta), no el que lo ha dado.
- Pasan mucho más: si les presionan, si llevan el balón más de 1,8 s o si hay un compañero mejor colocado.

## V0.37: formación más abierta + marca de versión
- Formación mucho más separada (el campo mide 140 x 80): en defensa dos jugadores a 18 studs por detrás del balón y
  el tercero a 36; en ataque el pívot 26 por delante, el ala abierto a 26 de la banda y el cierre 22 por detrás.
- Solo se marca a los rivales que están cerca de la propia portería.
- Al darle a Jugar, la Salida muestra `[Boot] FutbolGacha V0.37` y, al empezar el partido,
  `[Bots] Cerebro de los bots V0.37`. El proyecto de Rojo se llama "FutbolGacha V0.37".
- Los bots ya no se caen al chocar (antes se quedaban tumbados y no podían moverse): estados de caída desactivados
  y un AlignOrientation que los mantiene de pie.

## V0.38: cerebro táctico nuevo + pase cargable + barra de carga
- Script nuevo: `src/server/Services/Tactics.lua` -> ServerScriptService > Services > Tactics (ModuleScript).
  `BotBrain` ahora solo une Roblox con Tactics.
- Los bots calculan, para cada pase posible, si algún rival llega a cortarlo (tiempo del balón vs. tiempo del rival),
  valoran cada zona del campo (peligro) y comparan tirar / pasar (al pie o al hueco) / conducir (incluido proteger el
  balón y salir hacia atrás). Sin balón buscan el mejor hueco cerca de su puesto (pívot arriba, apoyo atrás y abierto).
  En defensa: uno presiona por el lado de su portería, otro cubre (o tapa el tiro) y otro marca al más peligroso.
- Probado con un simulador de partidos (carpeta `herramientas/simulador`): ~90 % de pases completados, ~40 pases/min,
  separación media entre compañeros ~25 studs y casi nunca 4 o más jugadores alrededor del balón.
- Regla nueva del balón: justo tras un golpeo (0,15 s) solo puede cortarlo quien esté en su trayectoria
  (antes el que te presionaba se quedaba el pase al instante).
- Pase cargable: mantén E (como el tiro). Barra de carga encima de la de resistencia para pase, tiro y tiro alto.
  Ayuda de pase: si un compañero está dentro de un cono de 22° hacia donde miras, el pase va hacia él.
- Ajustes: `Balance.Bots` (cerebro), `Balance.Kick.PassSpeedTap/PassSpeedFull/PassAssist...` (pase cargable).

## V0.39: campos más grandes + bots probados en el campo nuevo
- Campo 140 x 80 -> 165 x 95 (+18 %). Áreas, círculo central, esquinas, formación inicial y distancias de los bots
  crecen en proporción. Las gradas, sus curvas y el túnel de vestuarios ya salían del tamaño del campo: crecen solos.
- Campo de exhibición del lobby: se recoloca solo según el ancho (su muro con la puerta sigue pegado al paseo) y su
  grada mide el largo del campo menos 20.
- Cámara algo más cercana (Height 36, Back 29) y tiros algo más lentos (56-100).
- Regla nueva del balón: un balón rápido solo lo controla quien lo tiene viniéndole de frente (o pegado a él). Sustituye
  a la protección de 0,15 s de la V0.38 (el que presionaba al que pasaba se quedaba el pase en cuanto acababa).
- Bots (probados con el simulador en el campo nuevo): pases que tienen en cuenta que el receptor gana el balón si está
  más cerca (antes no pasaban a quien tenía el marcador a la espalda), pívot centrado delante del área, alas que suben
  por fuera cuando el balón está atrás, urgencia si llevan rato sin avanzar, croqueta valorada como una opción más.

## V0.40: cada uno en su sitio + robar siendo humano
- Posiciones por slot (`Balance.Bots.Positions`): 1 Delantero, 2 Medio, 3 Defensa, cada una con su zona de actividad
  (`Balance.Bots.Zones`). En ataque: delantero = pívot, medio = ala, defensa = cierre (atrás, pase de seguridad).
  En defensa: presiona sobre todo el delantero, el medio corta el pase al atacante más peligroso y el defensa cubre
  la espalda (o marca al que se le cuela). El defensa no se va al ataque conduciendo y suelta antes el balón.
- Robar siendo humano: se compensa el retraso de red (tu posición se adelanta 0,1 s según tu velocidad), +2 de
  alcance en entrada y segada, no hace falta mirar exacto, +12 % de probabilidad, robo por contacto algo más fácil.
  Si el rival te esquiva con una croqueta ya no te quedas aturdido. Los bots roban un 15 % menos a los humanos.
  Ajustes en `Balance.Control` (Human...).

## V0.41: entrada con impulso, pedir el balón, pases con "imán"
- Entrada (Q): ahora es un pequeño impulso (0,28 s) hacia el rival con balón si está a menos de 14 studs (si no, hacia
  donde miras) y durante el impulso intenta robar en cada fotograma. Antes era un intento instantáneo: si el servidor
  te veía un pelo lejos no pasaba nada visible. En Studio, la Salida escribe `[Entrada] Tu nombre: Won/Failed/Dodged`.
- E sin balón (y sin un balón suelto a tu alcance): pides el balón. Sale un bocadillo "¡Pásala!" sobre tu cabeza y,
  durante 2,5 s, el compañero bot que la tiene decide enseguida y prefiere pasártela si el pase es mínimamente seguro.
  Sonido `Balance.Sounds.Call` (pon tu ID si quieres otro).
- Pases más fuertes (humano 36-92, antes 24-72; bots algo más fuertes también) y con "mini-imán": si pasas mirando
  más o menos a un compañero (cono de 32°), el pase sale hacia él y, mientras viaja, se curva un poco hacia él y frena
  al llegar para que pueda controlarlo en vez de pasarse de largo. Ajustes en `Balance.Kick` (PassAssist..., Magnet...).
- Barras de carga más rápidas: `Balance.Control.ChargeSeconds` = 0,55 (antes 1,0).
- El medio ya casi no presiona: fuera de nuestro tercio solo presiona el delantero (o quien ya esté encima del balón),
  y el medio se queda siempre al menos 8 studs por detrás del delantero (`Balance.Bots.MedioBehind`, zona del medio
  hasta 0,55). En el simulador: medio por delante del delantero 0-1 % del tiempo (antes 2-8 %), medio presionando
  1-2 % (antes 13-14 %).

## V0.50: economía, brainrots, cajas y granjas con robos
**Qué hay nuevo**
- **Brainrots** (`src/shared/Config/Brainrots.lua`): 36 brainrots con su **fama**. La fama decide la **calidad**:
  Común < Raro < Épico < Legendario < Mítico < Secreto (colores como en CS:GO). Cada copia puede salir **Normal,
  Oro (x1,5 monedas) o Diamante (x2,5)**. Cada uno tiene un puesto ideal (delantero, medio, defensa, portero).
- **Niveles de brainrot** (hasta 25, se pagan con monedas): más monedas por segundo y mejores estadísticas.
- **Granjas** a la izquierda del spawn (paso abierto en la pared este del lobby): 8 granjas por servidor con 10
  pedestales. Los brainrots colocados te dan **monedas cada segundo** (y un 25 % mientras no estás, hasta 3 h).
- **Robos**: en la granja de otro, mantén "Robar" en un pedestal. Lo llevas sobre la cabeza (más lento) y tienes
  45 s para llegar a tu granja; si su dueño te alcanza, lo recupera. **Defensa**: pisa el botón rojo de tu granja
  (bloqueo de 60 s, láser en la entrada que echa a los intrusos). Tu granja está protegida 2 min al entrar al servidor
  y **mientras juegas un partido**.
- **Cajas** (con gemas): Básica 100, Épica 300 y Legendaria 800, con apertura **estilo CS:GO** (la tira de tarjetas
  frena y se para en el premio; el premio lo decide el servidor).
- **Equipo**: eliges 4 brainrots (1 Delantero = tú, 2 Medio, 3 Defensa, 4 Portero). En el partido se ven sus
  modelos y juegan con sus estadísticas (calidad + nivel + variante). El rival tiene un nivel parecido al tuyo.
  Huecos vacíos: juega un suplente.
- **Recompensas**: por partido (victoria/empate/derrota + por gol: monedas, gemas y XP), **nivel de cuenta** (XP →
  monedas y gemas al subir), **recompensa diaria** de 7 días seguidos, **canje** de monedas por gemas (caro) y
  **gemas con Robux**.
- Interfaz: arriba a la derecha monedas, gemas, nivel y monedas/s; a la izquierda el menú (Brainrots, Cajas, Tienda,
  Diario, Mi granja). En los pedestales de tu granja, "Ver" abre ese brainrot.

**Qué tienes que hacer tú**
1. **Guardado**: publica el juego y en Studio activa *Game Settings > Security > Enable Studio Access to API
   Services*. Sin eso funciona igual pero con datos temporales (sale un aviso rojo bajo el HUD).
2. **Gemas con Robux**: crea los Developer Products en create.roblox.com (tu juego > Monetización > Productos de
   desarrollador) y pega cada ID en `Economy.RobuxProducts` (con 0 salen como "Sin configurar").
3. **Modelos de brainrots**: crea una carpeta `BrainrotModels` dentro de ReplicatedStorage y mete cada modelo con el
   **mismo nombre que su Id** (por ejemplo `tralalero_tralala`). Se escala solo y se le quitan los scripts. Si un
   modelo sale mirando hacia atrás, gíralo 180° dentro de su carpeta. Sin modelo se ve un muñeco genérico de colores.
4. **Tamaño del servidor**: 8 jugadores (Game Settings > Places), igual que `Economy.Farm.Plots`.
5. Para probar los robos en Studio: *Test > Clients and Servers* con 2 jugadores (y baja
   `Economy.Farm.NewPlayerShieldSeconds` para no esperar 2 minutos).

Todos los números (precios, probabilidades, recompensas, ingresos, robos) están en `src/shared/Config/Economy.lua`.

## V0.51
- **Saltar la animación de las cajas**: Game Pass de pago único (99 R$). Crea el pase en create.roblox.com y pega su
  ID en `Economy.SkipSpinGamePassId`. Sin pase el botón ofrece comprarlo; con el pase, salta. Con 0 no aparece.
- **Iconos propios** de monedas y gemas: `Economy.Icons` (ID de la imagen). Vacío = icono dibujado.
- **Subir de nivel exponencial**: cada nivel multiplica las monedas por segundo (Común x1,10 ... Secreto x1,18) y el
  coste también sube de forma exponencial (Común x1,20 ... Secreto x1,25 por nivel). Los raros cuestan más pero rinden
  más (se recuperan antes). Se ajusta por calidad en `Brainrots.lua` (LevelGrowth, LevelCost, LevelCostGrowth).
  Al vender te devuelven además el 40 % de lo gastado en niveles.
- Partido: el cuerpo solo se esconde si el modelo del brainrot se creó bien; en Studio la Salida dice con qué brainrot
  juega cada uno (`[Match] ... juega como ...`) y comprueba el tuyo (`[Brainrot] ...`).
  `Balance.Match.BrainrotLook = false` vuelve al aspecto normal de Roblox.


## V0.60: rendimiento, bots que juegan contigo y granjas nuevas
**Archivo nuevo**: `src/client/Controllers/LobbyController.lua` -> StarterPlayerScripts > Controllers > LobbyController
(ModuleScript). Con Rojo no tienes que hacer nada.

**Rendimiento**
- Cerebro de los bots (`Tactics.lua`) unas 4 veces más rápido y sin tirones: antes, al repartir posiciones, un partido
  podía gastar 12-18 ms en un solo fotograma del servidor; ahora como mucho ~4 ms (medido con el simulador). Las
  decisiones son exactamente las mismas: solo calcula la parte cara para los sitios que aún pueden ser el mejor, y ya
  no crea tablas nuevas en cada cálculo. Además usa compilación nativa de Luau (`--!native`).
- Estadios reutilizables: cada hueco de partido construye su estadio (~2.500 piezas) una sola vez y lo conserva en
  `Workspace > Estadios`. Antes se construía y destruía en cada partido (tirón en el servidor y miles de piezas enviadas
  a todos los jugadores). El del primer hueco se prepara al arrancar el servidor.
- Las animaciones del lobby (balón que flota, portal) las hace cada jugador en su ordenador (`LobbyController`): antes
  el servidor movía esas piezas 60 veces por segundo y las mandaba a todos.
- Granjas: los brainrots solo se animan si los tienes cerca y se mueven todos de una vez (`BulkMoveTo`).
- Inventario: ya no se rehacen todas las tarjetas (cada una con su modelo 3D) al pulsar una; solo cambia la que cambia.

**Bots**
- Te piden el balón: si llevas el balón y un compañero bot está desmarcado y mejor colocado (o te presionan), sale
  "¡Pásala!" sobre él y suena un aviso. Pasa mirando hacia él y la ayuda de pase hace el resto.
- Si pasas a un bot, ese bot va a por el balón (antes podía ir otro compañero).
- El portero saca con la mano al compañero mejor desmarcado (antes despejaba al azar). Si no hay nadie libre espera
  un poco (como mucho 3 s) y luego se conforma con un pase menos seguro o despeja.
- Se apartan para no chocar con quien tienen delante al recolocarse (en el simulador, un 17 % menos de choques).
- Ajustes nuevos en `Balance.Bots`: `Call...` (pedir el balón), `Keeper...` (saque del portero), `Avoid...` (choques).

**Granjas**
- Zona nueva: muros de piedra con valla de madera, arco en la puerta con el nombre del dueño, cartel con su cara,
  camino y plaza de piedra, árboles, farolas, fuente al final de la avenida y tablero **TOP GRANJAS** (las que más
  monedas/s dan en el servidor) en el lobby, junto al paso a las granjas.
- El anillo de cada pedestal tiene el color de la calidad del brainrot (oro / diamante: el de la variante).
- "Colocar" en un pedestal vacío de tu granja: pone ahí tu mejor brainrot sin colocar.
- Botón **Colocar los mejores en la granja** en la ventana de Brainrots: llena la granja con los que más monedas dan.
- Sobre tus brainrots salen las monedas que van dando ("+12").
- Robos: el ladrón brilla en rojo (se ve a través de las paredes) y su dueño ve "¡LADRÓN!" sobre él; el ladrón ve una
  línea verde hasta su granja. El botón de bloqueo muestra su estado (BLOQUEAR / segundos bloqueada / espera).
- Corregido: el botón "Subir nivel" no se activaba al llegar a las monedas con la ventana abierta; si el dueño se va
  del servidor mientras le roban, el ladrón ahora recibe un aviso.

## V0.70: economía grande, niveles hasta 100 con evoluciones y granjas alrededor del spawn
**Economía** (todo en `Economy.lua` y `Brainrots.lua`)
- Números unas 10 veces más grandes: monedas por segundo (Común 25/s ... Secreto 4.500/s a nivel 1), precios de las
  cajas (1.000 / 3.000 / 8.000 gemas), recompensas, diario, canje y packs de Robux. **Las cuentas guardadas se
  convierten solas** al entrar: sus monedas y gemas se multiplican por 10 (`Economy.Data.MigrateV1Factor`).
- Niveles de brainrot hasta **100**. Cada nivel da más dinero (+4,5 % Común ... +6 % Secreto, compuesto) y cuesta más
  (+11 % ... +12 % por nivel): los primeros niveles vuelan y los últimos son un objetivo largo. Con el simulador
  (jugando sin parar): primera evolución a ~1 h 15 min, segunda a ~10 h, granja entera a nivel 100 a ~20 h.
- **El nivel casi no cambia el partido**: todos empiezan jugables (estadística base Común 58 ... Secreto 78) y 100
  niveles suman solo +6 (+2 por cada evolución). Oro y Diamante dan +2 / +4.
- Botones **Subir nivel** y **+10 niveles** en la ventana de Brainrots.

**Evoluciones** (`Brainrots.Evolutions`)
- Nivel 50 (★ Evolucionado): x1,3 de tamaño, x1,5 monedas; pinchos dorados, hombreras, emblema y aura.
- Nivel 90 (★★ Ascendido): x1,6 de tamaño, x2 monedas más (x3 en total); además alas de luz, halo y destellos.
- Es el mismo brainrot (mismo cuerpo, colores y adorno), con su evolución en la granja, el inventario, las cajas y el
  partido (allí crece menos para no tapar). Subir al nivel que evoluciona cuesta x5 / x8.
- Modelos propios: `ReplicatedStorage > BrainrotModels > <Id>_Evo1` y `<Id>_Evo2` (opcionales). Si no existen se usa
  el modelo normal con los adornos.

**Granjas alrededor del spawn**
- El lobby ya no está cerrado: es el centro del mapa. Las 8 granjas forman un anillo a 260 studs (`Economy.Farm.RingRadius`),
  a unos 170 studs unas de otras, con un camino de piedra con farolas desde el lobby hasta cada una. El oeste queda libre
  para el campo de exhibición. Cada granja tiene un letrero flotante ("Granja de ...") que se ve desde lejos.
- Granjas más grandes y pedestales más separados para los brainrots evolucionados.
- Tiempo para llevar un robo a tu granja: 75 s (las granjas están lejos).

**Bloqueo**
- Dura 90 s (`Economy.Farm.LockSeconds`).
- **Al entrar a un partido tu granja se bloquea sola** (láser en la puerta, nadie puede entrar ni robar).
- Si ya tenías un bloqueo, se congela mientras juegas y al volver te queda la mitad: entras con 60 s y sales con 30 s
  (`Economy.Farm.MatchLockResumeFactor`).

## V0.71: pases de los bots, robos cerca de la portería, tiros y regates
- **Pases de los bots**: salen desde el balón hacia el punto elegido (antes, hacia donde miraba el cuerpo), siempre con
  "mini-imán" hacia el compañero, con menos error (`Bots.PassErrorFactor` = 0,35) y más fuerza (`Bots.PassArrive` 19 y
  `Bots.PassPowerFactor` = 1,2: en Roblox el balón frena más de lo que calculaba el cerebro).
- **Sonido**: los golpeos suenan enteros hasta 55 studs de la cámara (antes 12; la cámara va a ~45 del jugador y los
  pases de los bots apenas se oían).
- **Robar cerca de su portería**: cuanto más cerca de su propia portería, más fácil roban los brainrots (bots): hasta
  +25 % en entradas y segadas y robo por contacto x2,5 pegados a ella (`Control.HomeStealRange/HomeTackleBonus/
  HomeContactBonus`).
- **Tiros**: tiran más (`Bots.ShootBias` 6, `ShootRange` 55) y al palo que eligen (la ayuda de puntería de los
  humanos ya no les desvía el tiro al centro).
- **Regates**: croquetas más a menudo y **sombrero** nuevo cuando tienen un rival justo delante (`Bots.Flick...`).

## V0.72: saque de centro libre y zona del portero
- **Saque de centro**: en cuanto se hace el pase de saque, los rivales ya pueden entrar en el círculo central (antes
  tenían que esperar 2 s más). `Balance.Kickoff.KeepOutSeconds = 0`.
- **Portero con el balón en las manos**: los rivales que estén en el primer tercio del campo (desde su portería) corren
  hacia atrás solos hasta salir de él; es obligatorio, también para ti. Los bots se dan la vuelta y corren hacia su
  campo, y no vuelven a entrar mientras el portero tenga el balón. El portero espera a que salgan (como mucho 5 s,
  `Bots.KeeperMaxHold`) y después saca. Ajustes en `Balance.Goalkeeper.ClearZone...` y `ClearRunFactor`.

## V0.73: interfaz estilo simulador
- **Estilo común** (`UiKit.lua`): colores vivos con degradado, bordes gruesos azul oscuro, esquinas redondeadas, letra
  redondeada **FredokaOne** blanca con contorno, iconos grandes (emojis) y botones que se hunden al pulsarlos.
  `UiKit.theme` aplica la letra y el contorno a todos los textos de nuestras pantallas (también sorteo, partido,
  ajustes y panel de pruebas).
- **HUD a la izquierda**: monedas y gemas en "píldoras" con un "+" verde (abre la tienda) y las monedas/s debajo; nivel
  con barra de XP; menú de losetas con icono (🧠 Brainrots, 🎁 Cajas, 🛒 Tienda, 📅 Diario, 🏡 Mi granja) y un
  puntito rojo cuando hay algo pendiente (diario sin cobrar, gemas para abrir una caja).
- **Ventanas** tipo "taquilla": azul claro, borde grueso, título con icono arriba a la izquierda, monedas y gemas arriba a
  la derecha y botón rojo de cerrar en la esquina. Tarjetas de brainrot del color de su calidad con franja de estado.
- **Tienda** nueva: pestañas (💎 Gemas / 💰 Canjear monedas), tarjetas con franja de precio y detalle a la derecha con
  un gran botón verde de comprar.
- Avisos de color según el tipo (✅ premio, ⚠️ cuidado, ⭐ nivel, 💬 info), botón ⚽ de jugar, marcador y ajustes con el
  mismo estilo. Iconos propios de monedas y gemas: `Economy.Icons` (como antes).

## V0.74: menús a los dos lados y códigos promocionales
- **Izquierda** (algo más arriba): monedas, gemas y nivel; debajo 🧠 Brainrots y 🏡 Mi granja.
- **Derecha** (debajo del engranaje de ajustes): 📅 Diario, 🎁 Cajas, 🛒 Tienda y 🎟️ Códigos.
- **Códigos promocionales**: ventana nueva (`CodesPanel.lua`, ModuleScript en StarterPlayerScripts > Controllers).
  Los códigos se crean en `Economy.Codes` (monedas, gemas, un brainrot de regalo y fecha de caducidad opcional).
  Cada jugador puede canjear cada código una vez (se guarda en sus datos). Da igual mayúsculas o espacios.

## V0.75: vehículos, tienda nueva, cajas x5 y gemas más difíciles
**Archivos nuevos**: `src/shared/Config/Vehicles.lua` y `src/shared/Util/VehicleModel.lua` (ModuleScript en
ReplicatedStorage > Shared > Config / Util), `src/server/Services/VehicleService.lua` (ServerScriptService > Services) y
`src/client/Controllers/GaragePanel.lua` (StarterPlayerScripts > Controllers). Con Rojo no tienes que hacer nada.

- **Vehículos (🛹 Garaje)**: cada 25 niveles de cuenta (1, 25, 50, 75, 100) se desbloquea un escalón con dos vehículos:
  uno de monedas y otro de 💎 gemas (algo mejor: un poco más rápido, salta algo más y deja estela, pero nunca
  mejor que el de monedas del escalón siguiente). Monopatín / Patinete
  eléctrico, Bicicleta / Bici Turbo, Hoverboard / Hoverboard Neón, Moto / Moto Voladora, Alfombra Mágica / Tabla
  Cohete. Montar / bajar con **V** o el botón de abajo. Solo fuera de los partidos; para robar hay que bajarse.
  Todo se ajusta en `Vehicles.lua`. Modelos propios: `ReplicatedStorage > VehicleModels > <Id>` (opcional).
- **Tienda** al estilo de las tiendas de los simuladores: categorías a la izquierda (⭐ Destacado, 🎁 Cajas, 💎 Gemas,
  💰 Canje, 🛹 Vehículos), banner arcoíris de la mejor caja con sus premios y botones **x1 / x5**, y a la derecha
  **📢 Últimos premios** del servidor (Épicos o mejores, Oro y Diamante). Los Míticos y Secretos se anuncian a todos.
- **Cajas**: hasta 5 a la vez (`Economy.MaxCasesAtOnce`), ruleta más larga (9 s, `Economy.CaseSpinSeconds`) con las
  tiras parándose una tras otra y resumen de todos los premios. **Saltar animaciones**: Game Pass de pago único
  (`Economy.SkipSpinGamePassId`): con el pase se saltan todas para siempre.
- **Canje de gemas mucho más caro**: cuesta lo que gana tu granja en 30 min / 8 h / 36 h (y como poco 1M / 5M / 25M
  monedas), así nunca sale barato. `Economy.Exchange`.
- **Iconos**: moneda de oro clásica (dibujada) y diamante 💎. Siguen pudiendo ser imágenes propias (`Economy.Icons`).

## V0.76: jaula de láser en las granjas bloqueadas
- Con la granja bloqueada (botón rojo o mientras su dueño juega un partido) la rodea una **jaula de láser**: los 4 lados
  y el techo, con barras rojas y rosas que palpitan, postes de luz en las esquinas, campo de fuerza translúcido y un
  "escáner" que sube y baja. Se enciende y se apaga con un fundido. La animación la hace cada jugador en su ordenador.
- **Es sólida**: nadie puede entrar (ni saltando el muro). Solo la atraviesa su dueño (grupos de colisión
  `FarmCage<n>` / `FarmOwner<n>`). Quien ya estaba dentro al bloquear es expulsado como antes; un ladrón que esté
  dentro con un brainrot robado queda atrapado hasta que su dueño le alcance o se acabe el tiempo.

## V0.77: optimización

- Cliente: las animaciones de la granja (brainrots, jaula de láser, cintas) y los brainrots del partido usan listas
  propias que se rellenan al aparecer cada pieza: ya no se pide `GetTagged` ni se leen atributos en cada fotograma.
  La jaula se agrupa por granja (apagada o lejana no cuesta nada) y solo se escribe la transparencia cuando cambia.
  De las cintas solo se mueven las flechas cercanas a la cámara. HUD, marcador y monedas solo se pintan al cambiar.
- Servidor: la energía del jugador solo se publica cuando cambia el número; la velocidad de la animación de correr
  de los bots solo se ajusta si cambia de verdad; los carteles de las granjas solo se tocan cuando cambian.

## V0.80: partidos ONLINE entre jugadores

- **Botones de jugar** (abajo en el centro): "⚽ Práctica" (contra bots, como antes) y "⚔️ JUGAR ONLINE". Encima,
  tu rango y tus copas (abre la ventana ONLINE).
- **Cola**: el servidor junta cada segundo a los que buscan en dos equipos de hasta 3 personas (el portero siempre es
  bot; los huecos, bots con los brainrots del capitán). Prioriza meter a más gente, equipos con las mismas personas y
  copas parecidas (la diferencia permitida crece con la espera). Cuando ya se puede jugar espera 12 s a que entre
  más gente (o empieza al momento con 6). Mientras buscas puedes seguir jugando (aviso arriba con el tiempo).
- **Grupos de amigos**: en la ventana ONLINE invitas a gente del servidor (hasta 3). Jugáis siempre juntos; solo el
  líder busca partido.
- **Copas (Elo) y rangos**: Bronce, Plata, Oro, Platino, Diamante, Campeón y Leyenda (con divisiones III, II, I).
  Primeras 5 partidas de colocación (suben y bajan más). Rachas de victorias dan copas extra. Abandonar = derrota.
- **Igualdad**: en online las estadísticas de los brainrots se acercan a la media del partido (`Ranked.StatEqualize`).
- **Abandonos**: si alguien se va, un bot ocupa su puesto al momento; si un equipo se queda sin personas, gana el otro.
- **Recompensas**: x1,5 monedas y XP, x1,25 gemas; el MVP (más goles) se lleva +50 gemas. Pantalla final con copas,
  subida / bajada de rango, racha y MVP.
- **Presentación VS** al empezar, con los nombres y rangos de cada equipo, y **etiquetas** sobre cada persona en el
  campo (nombre y rango, del color de su equipo).
- **Clasificación mundial** (OrderedDataStore "FG_Copas_v1"; en Studio sin acceso a la API, la del servidor) y
  columna "Copas" en la lista de jugadores.
- Configuración: `src/shared/Config/Ranked.lua`. Servidor: `RankedService.lua`. Cliente: `RankedPanel.lua`.
- **Probar en Studio**: Test > Clients and Servers con 2 o más jugadores y pulsar "JUGAR ONLINE" en cada uno. Solo,
  si llevas 6 s en la cola, juegas un partido online de prueba contra bots. En el panel de Pruebas puedes cambiar
  tus copas para ver los rangos.

## V0.81: emparejamiento entre TODOS los servidores

- La cola online es global (MemoryStore): cada servidor publica sus grupos y uno de ellos hace de emparejador
  (cerrojo que se renueva). Con el mismo reparto de siempre (más gente, equipos iguales, copas parecidas).
- Si todos los elegidos están en el mismo servidor, se juega allí. Si no, se reserva un servidor para el partido
  (`TeleportService:ReserveServer`), viajan todos juntos y al acabar cada uno vuelve a su servidor de antes (o a
  otro si el suyo está lleno). El servidor del partido espera hasta 40 s a que lleguen todos; si un equipo entero no
  llega, se cancela sin perder copas.
- En Studio no se puede viajar entre servidores: allí la cola sigue siendo la del servidor. Si MemoryStore falla en
  el juego publicado, durante 60 s también se usa la del servidor.
- Archivos: `GlobalMatchmaking.lua` (cola global y servidor de partido) y `RankedService.lua`.
  Ajustes en `Ranked.lua`: `Global`, `GlobalTick`, `MatchServerWait`.

## V0.82: ofertas especiales (Robux, una vez por jugador)

- **Pack de bienvenida** (`Economy.Offers.Starter`): 2.500 gemas + 50.000 monedas por ~19 R$, solo los 3 primeros
  días desde que entras (los jugadores antiguos tienen 3 días desde esta versión).
- **Rayo de Lanzamiento** (`Economy.Offers.LaunchVehicle`, vehículo "launchbolt" de Vehicles.lua): 49 R$, velocidad
  31 desde el nivel 1 (como un hoverboard de nivel 50) y con estela.
- Se ven en: tarjetas animadas a la derecha de la pantalla, una pantalla de ofertas que sale sola al entrar (una vez
  por sesión), arriba de la pestaña Destacado de la tienda y arriba del Garaje (el vehículo).
- Son productos de desarrollador: pon sus IDs en `Economy.Offers` (con 0 no aparecen).
- Archivos: `Offers.lua` (lógica cliente), `OffersPanel.lua` (tarjetas y pantalla), `EconomyService.processReceipt`.

## V0.83: primeros modelos 3D reales de brainrots

- 10 brainrots nuevos en `Brainrots.lua` (Avocadorilla, Raffalello Il Porcello, Santteo, Karkerkar Kurkur, Ketupat
  Kepat, Swag Soda, To To To Sahur, Celularcini Viciosini, 67 Sessantasette, Il Boss Finalissimo) y modelos para
  Bombardiro Crocodilo y Udin Din Din Dun. Total: 46 brainrots.
- Los modelos (.glb, carpeta ../Brainrots) se importan en Studio y se colocan con `herramientas/colocar_brainrots.lua`
  (barra de comandos). Quedan en ReplicatedStorage > BrainrotModels (se guardan con el sitio).
- `Brainrots.ModelYaw`: giro de cada modelo propio para que mire hacia delante (los de Sketchfab, 180).
- Créditos obligatorios (CC BY 4.0) en `CREDITOS.txt`.

## V0.84: arreglos de los modelos 3D

- **No se veían en los partidos** (ni el brainrot robado sobre la cabeza): las piezas iban unidas con WeldConstraint
  y, al mover solo la base antes de meter el modelo en el mundo, el resto se quedaba en el centro del mapa. Ahora van
  con Weld (sitio fijo) y se mueve el modelo entero (`PivotTo`).
- **Salían grises**: 6 modelos de Sketchfab guardan el color en el formato antiguo `KHR_materials_pbrSpecularGlossiness`,
  que Roblox no importa. `herramientas/arreglar_glb.ps1` lo pasa al formato normal y convierte los colores sin textura
  en texturas pequeñas (las texturas siempre se importan). Corregidos en `../Brainrots/Corregidos`.
- **Algunos de espaldas**: cada modelo se miró desde sus 4 lados; `Brainrots.ModelYaw` tiene ya el giro de cada uno.
