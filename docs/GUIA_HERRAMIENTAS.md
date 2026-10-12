# Guía de uso de las herramientas de Open WebUI

Esta guía explica cómo usar en el chat las herramientas que el instalador añade a Open WebUI: búsqueda en internet, lectura de documentos, hora y lectura de páginas web, y el terminal. La última sección es para quien administra el servidor.

> Las imágenes son esquemas, no capturas. Usan los textos exactos de Open WebUI 0.11.3 en español, incluidas algunas erratas de su traducción (por ejemplo «Servidores de Herraientas»). La apariencia real puede variar con la versión.

## Qué herramientas hay

| Herramienta | Para qué sirve | Dónde se activa |
|---|---|---|
| **Búsqueda Web** (SearXNG) | Preguntas sobre información actual, con las fuentes citadas | Integraciones › Búsqueda Web |
| **Documentos** (Apache Tika) | Hacer preguntas sobre PDF, Word, Excel y PowerPoint | Más (+) › Subir Archivos o Adjuntar Conocimiento |
| **time** (mcpo) | Hora actual y conversiones entre zonas horarias | Herramientas |
| **fetch** (mcpo) | Leer y resumir una página web concreta | Herramientas |
| **wikipedia** y **arxiv** (mcpo) | Consultar la Wikipedia en español y buscar artículos científicos | Herramientas |
| **Terminal** (Open Terminal) | Ejecutar comandos, analizar datos, crear archivos de Word, Excel, PowerPoint y PDF | Integraciones › Terminal |
| **Memoria** (incluida en Open WebUI) | Que el modelo recuerde datos tuyos entre chats | Ajustes › Personalización › Memoria |
| **Interprete de Código** (Jupyter) | Que el modelo calcule con Python y dibuje gráficos dentro del chat | Integraciones › Interprete de Código |
| **Voz** (Whisper y Piper) | Dictar en vez de escribir y escuchar las respuestas | Botones Dictar y Modo de Voz; altavoz en cada respuesta |

Todas funcionan dentro del servidor. Tus documentos y conversaciones no salen de él; solo las búsquedas web y las páginas que pidas leer viajan a internet.

## Antes de empezar

![Barra de escritura del chat con los botones Más, Herramientas e Integraciones](images/herramientas/barra-chat.svg)

- **Las herramientas se activan en cada chat**, desde la barra de escritura. Un chat nuevo empieza sin ellas.
- **Elige un modelo capaz.** Para usar herramientas y el terminal funcionan bien los modelos de la familia qwen3.5. Los modelos muy pequeños no saben usarlas.
- **Si no ves «Herramientas» o el terminal**, tu usuario no tiene acceso todavía. Pídeselo al administrador.

## 1. Buscar en internet

![Menú Integraciones con Búsqueda Web activada y el terminal seleccionado](images/herramientas/menu-integraciones.svg)

1. Abre **Integraciones** en la barra de escritura.
2. Activa **Búsqueda Web**.
3. Escribe tu pregunta como siempre.

El modelo genera las consultas, lee los mejores resultados (5 por defecto) y responde citando las fuentes.

![Respuesta con el aviso de búsqueda completada y las citas de las fuentes](images/herramientas/respuesta-fuentes.svg)

Ejemplos que funcionan bien:

- «¿Qué novedades trae la última versión de AlmaLinux? Resúmelas en una lista.»
- «Compara los precios actuales de las tarjetas RTX 4060 y RTX 3060 en tiendas españolas.»
- «¿Qué dice la documentación oficial de Python sobre `asyncio.TaskGroup`?»

Consejos:

- **Sé concreto**: indica el periodo («este año», «la última versión»), el país o el tipo de fuente que prefieres.
- **Comprueba las fuentes** en temas importantes. Pulsa una cita para abrirla: el modelo resume lo que encontró y puede equivocarse.
- **No pongas datos confidenciales** en una pregunta con la búsqueda activada: las consultas se envían a buscadores públicos (de forma anónima, a través de SearXNG).
- Desactiva la búsqueda cuando no la necesites; las respuestas serán más rápidas.
- Si el administrador instaló el lector con Chromium, también se leen bien las páginas que cargan su contenido con JavaScript (tiendas, webs modernas).

## 2. Trabajar con documentos

![Menú Más con Subir Archivos y Adjuntar Conocimiento](images/herramientas/menu-mas.svg)

Hay dos formas de usar documentos:

| | Subir Archivos | Adjuntar Conocimiento |
|---|---|---|
| Para qué | Un documento para la conversación actual | Una colección de documentos que reutilizas a menudo |
| Cómo | Más (+) › **Subir Archivos**, o arrastra el archivo al chat | Créala en **Espacio de Trabajo › Conocimiento** y en el chat usa Más (+) › **Adjuntar Conocimiento**, o escribe **#** y elígela |
| Dura | Solo en ese chat | Hasta que la borres; se puede compartir con otros usuarios |

Formatos: PDF, Word, Excel, PowerPoint, texto, Markdown, CSV y similares, también **PDF escaneados e imágenes con texto**: Apache Tika extrae el texto en el servidor y aplica OCR (reconocimiento de texto) en español e inglés cuando la página no tiene texto.

Ejemplos:

- «¿Qué plazo de entrega fija el contrato adjunto y qué penalización hay si se incumple?»
- «Haz una tabla con los importes por trimestre que aparecen en el informe.»
- «#manual-procedimientos ¿Cuál es el procedimiento para dar de alta a un proveedor?»

Ten en cuenta:

- **El modelo no lee el documento entero de golpe**: el servidor busca los fragmentos relacionados con tu pregunta (por significado y por palabras clave), los reordena con un modelo de relevancia y entrega los 5 mejores. Pregunta por temas concretos. Para resumir un documento largo, pide el resumen por capítulos o secciones.
- **Los PDF escaneados tardan más**: el OCR procesa cada página como una imagen. La calidad depende del escaneo; con fotos torcidas o borrosas el texto puede salir con errores.
- Si una respuesta no encaja con el documento, pide al modelo que cite el fragmento en el que se basa.

## 3. Hora y lectura de páginas (herramientas MCP)

![Menú Herramientas con time y fetch activadas](images/herramientas/menu-herramientas.svg)

1. Abre **Herramientas** en la barra de escritura.
2. Activa **time (mcpo)**, **fetch (mcpo)** o las dos.
3. Pide lo que necesites; el modelo decide cuándo usarlas.

| Herramienta | Ejemplos |
|---|---|
| time | «¿Qué hora es ahora en Tokio?» · «Si son las 10:00 en Madrid, ¿qué hora es en Nueva York?» |
| fetch | «Resume esta página: https://…» · «Lee esta noticia y dime qué cifras da: https://…» |
| wikipedia | «Según la Wikipedia, ¿cuándo se fundó la Universidad de Salamanca?» · «Resume el artículo sobre la fotosíntesis» |
| arxiv | «Busca en arXiv artículos recientes sobre reranking para RAG y resume los tres primeros» |

wikipedia y arxiv solo aparecen si el administrador los añadió.

**fetch o Búsqueda Web:**

- Usa **fetch** cuando ya tienes la dirección de la página.
- Usa **Búsqueda Web** cuando quieres que el modelo encuentre las páginas.
- Puedes combinarlas: busca con la Búsqueda Web y después pide «lee a fondo la segunda fuente».

fetch no puede leer páginas que piden inicio de sesión ni las que bloquean la lectura automática.

## 4. El terminal (Open Terminal)

Con el terminal, el modelo puede ejecutar comandos en el servidor: analizar un CSV con Python, convertir formatos, generar un informe o un gráfico y guardarlo como archivo.

1. Abre **Integraciones** y, en **Terminal**, elige **Open Terminal (this server)** (ver la imagen de la sección 1).
2. Pide la tarea con detalle: qué datos, qué resultado y en qué formato.
3. Revisa cada llamada al terminal: muestra el comando que ejecutó el modelo y su resultado.

![Chat usando el terminal, con el comando ejecutado y el panel de archivos](images/herramientas/terminal.svg)

Ejemplos:

- «Sube ventas.csv (adjunto). Calcula el total por mes con Python y guarda el resultado en resumen.csv.»
- «Convierte informe.md a HTML y dime cuántas palabras tiene.»
- «Crea un gráfico de barras con los datos de resumen.csv y guárdalo como grafico.png.»
- «Hazme un Excel con estos gastos (luz 60, agua 25, internet 30) y una fila de total con fórmula. Muéstramelo.»
- «Redacta una carta de reclamación en Word con este texto y muéstramela.»
- «Haz una presentación de 3 diapositivas sobre este resumen» o «…guárdalo como PDF».

El terminal crea archivos de **Word, Excel, PowerPoint y PDF**. Si le pides que te lo **muestre**, el archivo aparece en el chat con vista previa y botón de descarga.

> **Fórmulas de Excel:** dentro del archivo las fórmulas se guardan siempre en inglés (`SUM`, `IF`, `VLOOKUP`), aunque Excel las muestre en español. Si el modelo escribe `=SUMA(…)`, la celda saldrá con error al abrirla. Pídeselo así: «usa las fórmulas en inglés, como SUM».

Con **Mostrar Archivos** ves y descargas los archivos del espacio de trabajo.

Qué puede hacer y qué no:

| Puede | No puede |
|---|---|
| Ejecutar comandos y programas de Python | Usar `sudo` ni instalar paquetes del sistema |
| Crear, leer y modificar archivos en su espacio de trabajo | Escribir fuera de su espacio de trabajo |
| Usar Python 3 e instalar paquetes para sí mismo (`pip install --user pandas`) | Ver las carpetas personales de `/home` ni los procesos de otros servicios |
| Descargar datos de internet | Acceder a las claves de las demás herramientas |

**Importante:**

- **El espacio de trabajo es compartido** por todos los usuarios con acceso al terminal. Cualquiera de ellos puede ver tus archivos. No dejes datos confidenciales y borra lo que ya no necesites.
- **No escribas contraseñas ni claves** en el chat ni en archivos del terminal.
- **Revisa lo que hace el modelo** antes de usar sus resultados, sobre todo si modifica o borra archivos.

## 5. Memoria: que el modelo te recuerde

Open WebUI puede recordar datos tuyos entre chats («trabajo en contabilidad», «escríbeme siempre de tú»). Cada usuario tiene su propia memoria; nadie más la ve.

- Dile «recuerda que…» y el modelo lo guarda. En chats nuevos lo tendrá en cuenta.
- Revisa, edita o borra lo guardado en **Ajustes › Personalización › Memoria**.
- Funciona mejor con modelos de la familia qwen3.5 y la llamada a funciones en modo Nativo.

## 6. Cálculos y gráficos (Interprete de Código)

Si el administrador instaló Jupyter, el **Interprete de Código** ejecuta Python en el servidor, con pandas, numpy y matplotlib, y los gráficos aparecen dentro de la respuesta.

1. Abre **Integraciones** y activa **Interprete de Código** (si no aparece, no tienes permiso: pídeselo al administrador).
2. Pide cálculos o gráficos: el modelo escribe el código, lo ejecuta y te muestra el resultado.

Ejemplos:

- «Con estos datos (pega una tabla), calcula la media y la desviación por mes y haz un gráfico de líneas.»
- «Sube el Excel adjunto y dime qué producto creció más entre trimestres; dibuja un gráfico de barras.»
- «¿Cuánto es la cuota de un préstamo de 150.000 € a 25 años al 3,1 %? Haz la tabla del primer año.»

Ten en cuenta:

- El código se ejecuta en el servidor con los mismos límites que el terminal (sin `sudo`, solo en su carpeta). La carpeta de trabajo es **compartida**: no dejes datos confidenciales.
- Revisa el código y el resultado: el modelo puede equivocarse al programar.

## 7. Voz: dictar y escuchar

- **Dictar**: pulsa **Dictar** en la barra de escritura y habla; el texto aparece en el mensaje. **Modo de Voz** abre una conversación hablada. La transcripción se hace en el servidor (Whisper), sin enviar el audio fuera.
- **Escuchar**: en cada respuesta, el botón de altavoz la lee en voz alta (Piper, voces en español). Puedes elegir otra voz en Ajustes › Audio.
- El micrófono **solo funciona en la dirección `https://`** del servidor (ver la sección siguiente).

## Acceso seguro (HTTPS) y dictado por voz

Si el administrador activó HTTPS, entra en Open WebUI por la dirección `https://` que te indique (por ejemplo `https://svr32ai`). Así la conexión va cifrada y, además, el navegador te deja usar el micrófono para **Dictar** y el **Modo de Voz**; en la dirección `http://` los navegadores lo bloquean.

La primera vez el navegador avisará de que no reconoce el certificado, porque lo emite el propio servidor. Para quitar el aviso, instala una vez el certificado raíz:

1. Descárgalo desde `https://<dirección del servidor>/xemi-ca.crt` (acepta el aviso esa única vez).
2. Comprueba con el administrador que la huella SHA-256 coincide.
3. Instálalo como autoridad de certificación de confianza: el administrador tiene los pasos para Windows, macOS, Linux, Android e iOS (opción «Show HTTPS addresses and root certificate» del instalador).

## Combinaciones útiles

| Combinación | Ejemplo |
|---|---|
| Búsqueda Web + fetch | «Busca la guía oficial de instalación de X y luego lee la primera fuente a fondo.» |
| Documento + terminal | Sube un Excel y pide: «calcula las medias por columna y genera un gráfico». |
| Conocimiento + Búsqueda Web | «#politica-interna ¿Cumple nuestra política con lo que exige la normativa publicada este año?» |

## Problemas frecuentes

| Qué pasa | Por qué | Qué hacer |
|---|---|---|
| No veo «Herramientas» o el terminal | Tu usuario no tiene acceso | Pídeselo al administrador |
| El modelo no usa la herramienta | Modelo demasiado pequeño, o la herramienta no está activada en este chat | Usa un modelo de la familia qwen3.5 y comprueba el menú; dile explícitamente «usa la herramienta fetch» |
| La búsqueda no devuelve nada | Pregunta muy genérica, o el servicio de búsqueda está caído | Concreta la pregunta; si sigue fallando, avisa al administrador |
| El documento «no tiene texto» o sale con errores | Escaneo de baja calidad, o el OCR no está activado en el servidor | Prueba con un escaneo más nítido; si nunca funciona, avisa al administrador |
| El navegador no deja usar el micrófono | La página no es HTTPS | Entra por la dirección `https://` (ver «Acceso seguro») |
| La respuesta ignora parte del documento | El modelo solo ve los fragmentos más relevantes | Pregunta por secciones concretas |
| La respuesta se corta o el chat da error con mucho texto | Se superó el contexto del modelo | Empieza un chat nuevo o adjunta menos documentos a la vez |
| Con varias herramientas activas el modelo responde peor o se corta antes | Cada herramienta activa ocupa contexto con su descripción, y la búsqueda web añade el texto de las páginas | Activa solo las herramientas que necesites en ese chat |
| La búsqueda web cita menos fuentes de las esperadas | Alguna página no respondió a tiempo o bloquea los accesos automáticos | Repite la pregunta o pega directamente la dirección de la página |

## Para el administrador

### Dar acceso a usuarios

Las conexiones que crea el instalador son **privadas**: solo las ven los administradores. Para que otros usuarios usen el terminal o las herramientas MCP, da acceso a un grupo:

![Administración, Ajustes, Integraciones: editar una conexión y dar acceso a un grupo](images/herramientas/admin-permisos.svg)

1. **Administración › Ajustes › Integraciones**.
2. En la conexión, pulsa **Editar**.
3. En **Control de Permisos**, elige el grupo y guarda.

Los grupos se gestionan en **Administración › Usuarios › Grupos**. Da acceso al terminal solo a quien lo necesite: ejecuta comandos en el servidor y su espacio de trabajo es compartido. Si reconectas las herramientas con el instalador, los permisos que hayas dado se conservan.

La extracción de documentos funciona para todos los usuarios. La Búsqueda Web también está permitida por defecto; puedes limitarla por grupo en los permisos de cada grupo.

### Modelos que usan herramientas

![Espacio de Trabajo, Modelos: Modo de Llamada a Funciones en Nativo](images/herramientas/admin-modelo.svg)

En **Espacio de Trabajo › Modelos › (modelo) › Editar › Parámetros Avanzados**, deja **Modo de Llamada a Funciones (Herramientas)** en **Nativo**. Es el valor por defecto desde Open WebUI 0.10, pero conviene comprobarlo en los modelos que hayas personalizado.

### Qué hay detrás

![Esquema de Open WebUI, Ollama y las herramientas en el servidor](images/herramientas/arquitectura.svg)

- Las herramientas escuchan solo en `127.0.0.1` y Open WebUI las llama desde el propio servidor, así que no hace falta abrir sus puertos en el firewall.
- Los puertos del esquema son los de por defecto. Los reales están en `7) Services › Show status of all services` (columna `LISTEN`) o con `sudo /usr/local/bin/xemi_ai_install.sh services`.

### Mantenimiento con el instalador

| Tarea | Menú | Comando |
|---|---|---|
| Estado, puertos y salud de los servicios | 7) Services › Show status of all services | `services` |
| Comprobación general (incluye herramientas y aislamiento) | 8) Diagnostics › Run doctor readiness check | `doctor` |
| Conectar o reconectar las herramientas a Open WebUI | 5) Open WebUI tools › Connect installed tools to Open WebUI | `tools-connect` |
| Actualizar las herramientas y su aislamiento | 5) Open WebUI tools › Update installed tools | `tools-update` |
| Modelo de tareas, búsqueda híbrida con reranker y número de resultados | 4) Open WebUI › Apply recommended settings | — |
| Copias de seguridad de Open WebUI | 4) Open WebUI › Backups | `backup-setup`, `backup-now` |
| Acceso HTTPS y certificado raíz | 6) Network › Enable HTTPS / Show HTTPS addresses | `https-setup`, `https-info` |
| Añadir OCR a Tika en una instalación anterior | 5) Open WebUI tools › Update installed tools | `tools-update` |
| Dictado (Whisper) e idioma, voz de las respuestas | 4) Open WebUI › Voice settings | `voice-setup` |
| Instalar voz, Jupyter o el lector con Chromium | 5) Open WebUI tools › Install … | `piper-tts`, `jupyter`, `chromium` |
| Añadir o quitar Wikipedia y arXiv | 5) Open WebUI tools › Add or remove MCP servers in mcpo | `mcp-servers` |
| Contexto y caché de los modelos | 2) Ollama › Tune model memory | `ollama-tune` |
| Uso de GPU y modelos cargados | 7) Services › GPU usage | `gpu` |

Los comandos se ejecutan como `sudo /usr/local/bin/xemi_ai_install.sh <comando>`.

### HTTPS

`6) Network › Enable HTTPS access for Open WebUI` pone Caddy delante de Open WebUI, con una autoridad de certificación propia del servidor:

- Pregunta los nombres y las IP que usan los usuarios (por defecto, el nombre del servidor y sus IP) y el puerto (443).
- Abre ese puerto solo para la red local en el firewall.
- El certificado raíz se descarga en `https://<servidor>/xemi-ca.crt`. `Show HTTPS addresses and root certificate` muestra su huella SHA-256 y cómo instalarlo en cada sistema.
- La dirección `http://…:3000` sigue funcionando; indica a los usuarios que usen la de HTTPS.
- Al quitarlo se borran el servicio, la regla del firewall y la autoridad de certificación. Si vuelves a activarlo, se crea una nueva y hay que reinstalar el certificado en los equipos.

### Copias de seguridad

`4) Open WebUI › Backups` programa una copia diaria de Open WebUI: chats, usuarios, ajustes, conocimiento, archivos subidos e índice de búsqueda. La base de datos se copia de forma consistente aunque Open WebUI esté en uso.

- **Schedule daily backups**: carpeta, hora y cuántas copias conservar (7 por defecto). Si la carpeta está en el mismo disco que Open WebUI, el instalador lo avisa: copia las copias también a otro sitio.
- **Restore a backup**: antes de restaurar guarda una copia `pre-restore` del estado actual; si Open WebUI no arranca con los datos restaurados, vuelve solo a los anteriores. No restaura copias de una versión de Open WebUI más nueva que la instalada.
- Las copias contienen las conversaciones de todos los usuarios: el directorio es solo para root. Nunca se borran automáticamente al desinstalar.

### Interprete de Código en el servidor (Jupyter)

`5) Open WebUI tools › Install Jupyter code interpreter` instala Jupyter y lo conecta como motor de **Ejecución de código** y de **Interprete de Código**. Por defecto Open WebUI deja usar el intérprete a todos; al conectar, el instalador pregunta si mantenerlo y, si respondes que no, lo deja solo para administradores. Para dárselo a un grupo: **Administración › Usuarios › Grupos › (grupo) › Permisos › Interprete de Código**. Al quitar Jupyter, Open WebUI vuelve a ejecutar el código en el navegador (Pyodide) y se restaura el permiso anterior.

### Voz

- `5) Open WebUI tools › Install Piper text to speech` instala las voces `es_ES-davefx`, `es_ES-sharvard` y `en_US-lessac` y las conecta como voz de las respuestas.
- `4) Open WebUI › Voice settings` pone el dictado en Whisper `small` (el modelo por defecto, `base`, se equivoca en español) y fija el idioma (`es`, o `auto` para detectarlo). Cambiar el idioma reinicia Open WebUI durante un minuto y corta las respuestas que se estén generando: el instalador lo avisa y pide confirmación. Hazlo cuando nadie esté usando el chat.

### Lector de páginas con Chromium

`5) Open WebUI tools › Install Chromium web loader` hace que Open WebUI lea las páginas con un Chromium sin interfaz, en su propio usuario y aislado. Usa la versión de Playwright que declara Open WebUI y se resincroniza solo al actualizar Open WebUI. Instala también las fuentes del sistema (sin ellas Chromium se cierra en páginas con fuentes web) y, dentro de Open WebUI, el paquete `unstructured` que usa para extraer el texto, respetando las versiones que fija Open WebUI.

### Buscadores de SearXNG

Desde una sola IP de servidor, DuckDuckGo, Brave y Google acaban respondiendo con CAPTCHA o límites de uso y no devuelven nada. El instalador activa además Bing y Yahoo en `/etc/searxng/settings.yml` al instalar SearXNG y en `Update installed tools`.

### Servidores MCP adicionales

`5) Open WebUI tools › Add or remove MCP servers in mcpo` añade o quita `wikipedia` (Wikipedia en español) y `arxiv` (artículos científicos). Tras el cambio ofrece actualizar la conexión en Open WebUI; si no lo haces, la lista de herramientas de Open WebUI no reflejará el cambio.

### Búsqueda en documentos (reranker)

`4) Open WebUI › Apply recommended settings` activa la búsqueda híbrida: busca 10 fragmentos candidatos por significado y por palabras clave y un modelo multilingüe de relevancia (`cross-encoder/mmarco-mMiniLMv2-L12-H384-v1`) elige los 5 mejores. Corre en la CPU (unos 0,5 s por consulta en este servidor), sin quitar memoria de la GPU a los modelos. Open WebUI lo descarga (unos 470 MB) al aplicar el ajuste.

### Documentos en español: modelo de incrustación

En instalaciones nuevas, el instalador configura un modelo multilingüe para buscar dentro de los documentos. En instalaciones anteriores puede seguir el modelo original, pensado para inglés. Para cambiarlo:

1. **Administración › Ajustes › Documentos › Modelo de Incrustación**: `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2`.
2. Reindexa el conocimiento existente cuando Open WebUI lo pida. Los documentos indexados con el modelo anterior no se encuentran bien con el nuevo hasta reindexarlos.

### Seguridad

- **Terminal:** se ejecuta como el usuario `aiterminal`, sin `sudo`, con el sistema en solo lectura y sin ver los procesos de otros usuarios. Aun así, ejecuta lo que el modelo decida: limita el acceso a usuarios de confianza.
- **Claves:** las claves de Open Terminal y mcpo están en `/etc/xemi-ai/` (solo root). Open WebUI las guarda en su base de datos al conectar.
- **Ollama:** si `doctor` avisa de que escucha en todas las interfaces y nadie lo usa fuera de Open WebUI, cámbialo a `127.0.0.1` en `2) Ollama › Configure Ollama service for LAN`.
