# LeoneraKeyboard

Teclado personalizado para iOS escrito en SwiftUI, sin dependencias externas.

Cada tecla tiene una acción principal (el carácter grande) y, opcionalmente, una
acción secundaria que se muestra como un símbolo pequeño en la parte superior:

- **Tocar** la tecla escribe el carácter principal.
- **Deslizar hacia abajo** escribe el símbolo secundario o ejecuta su acción
  (emojis, pegar, borrar palabra…).

Mantener pulsadas las teclas de borrar o de mover el cursor repite la acción.
Pulsar dos veces mayúsculas activa el bloqueo de mayúsculas.

## Distribución por defecto

```
 1☺  2"  3#  4$  5%  6&  7/  8(  9)  0📋
 Q_  W\  Eé  R|  T<  Y>  Uú  Ií  Oó  P•
 Aá  S/  D:  F;  G[  H]  J¡  K!  L@  Ñ🎤(dictar)
 ⇧    Z+  X-  C*  V¿  B?  N,  M.    ⌫(borrar palabra)
 ⌨︎(ocultar)      espacio          ⏎
```

## Personalización

La app incluye un editor donde se puede:

- Editar cada tecla: acción principal, acción secundaria, etiqueta y ancho.
- Añadir, eliminar, reordenar y mover teclas entre filas; añadir, mover y eliminar filas.
- Ajustar mayúscula automática, minúsculas, sonido, alto de fila, la distancia
  de deslizamiento y el cursor (aceleración y velocidad máximas, y curva).
- Mover el cursor como con un trackpad: al mantener pulsada la barra espaciadora
  las teclas se quedan vacías y arrastrar el dedo a izquierda o derecha mueve el
  cursor. Los ajustes del cursor muestran una gráfica con la curva: la velocidad del
  cursor (en caracteres por segundo) depende de la aceleración del dedo (en puntos
  por segundo). Por debajo de la aceleración mínima el cursor no se mueve; a partir
  de ella sube según la curva, que va de lineal (1,0) a progresiva (2,5), hasta la
  aceleración máxima; por encima de ella el cursor va a la velocidad máxima. Cada carácter que avanza el cursor vibra según los ajustes de vibración.
- Definir el área de toque de cada tecla: forma cuadrada o circular, centrada en la
  tecla, con anchura y altura en porcentaje. Tocar fuera de esa área no hace nada.
  La barra espaciadora siempre ocupa toda la anchura; solo le afecta la altura.
  La vista previa de los ajustes muestra una tecla a tamaño real dentro de la forma.
- Configurar la vibración: tipo (Ligero, Medio, Fuerte, Suave o Rígido), intensidad y duración.
  La tecla vibra en cuanto se toca, tanto para el carácter principal como para el
  secundario (no espera a que se suelte). La vibración nunca hace esperar al teclado:
  se reproduce en segundo plano y cada pulsación corta la vibración anterior.
- Exportar e importar la configuración completa como JSON.
- Restablecer la distribución por defecto.

Acciones disponibles: texto, espacio, borrar, borrar palabra, mayúsculas, bloqueo
de mayúsculas, intro, tabulador, ocultar teclado, siguiente teclado, emojis, dictar,
pegar, copiar, cortar y mover el cursor.

## Dictado

La acción **Dictar** (en la distribución por defecto, deslizando hacia abajo la
tecla Ñ) cambia el teclado por una pantalla con un botón de grabar en el centro y
un interruptor **Mejorar texto con IA**:

1. Toca el botón para grabar y vuelve a tocarlo para terminar.
2. El audio se envía a Groq (`/audio/transcriptions`) para convertirlo en texto
   con el modelo de voz a texto elegido.
3. Con el interruptor activado, la transcripción se envía después al LLM elegido
   (`/chat/completions`) con un prompt que corrige la puntuación, los signos, la
   ortografía y que el texto tenga sentido.
4. El texto se escribe donde está el cursor.

En la app, **Dictado** permite configurar la API key, una URL de API personalizada
(cualquier servicio compatible con la API de OpenAI), los modelos de voz a texto y
LLM (se pueden escribir o elegir de la lista que devuelve la API), el idioma del
audio y el prompt. Por defecto se usan `whisper-large-v3-turbo` y
`openai/gpt-oss-120b`. Estos ajustes se guardan aparte y no se incluyen al exportar
la configuración, para no compartir la API key.

iOS normalmente no deja que un teclado use el micrófono, así que la app graba por
él: la primera vez que dictas, el teclado abre Leonera Keyboard, que activa el
micrófono y empieza a grabar; vuelve a la app anterior (botón «◀︎» de la barra de
estado) y termina la grabación desde el teclado. Por defecto, el micrófono se
cierra al salir de la pantalla de dictado, cambiar de app o cerrar el teclado. Si
activas **Cierre automático del micrófono** en Dictado, queda activo en segundo
plano (con el indicador naranja) para los siguientes dictados y se desactiva tras
5 minutos sin usarlo o desde la app. Si el sistema sí permite
grabar desde el teclado, se graba directamente sin abrir la app.

El teclado recuerda la pantalla que tenía abierta (teclado, emojis o dictado) y la
vuelve a mostrar al reaparecer, así que tras grabar en la app de Leonera vuelves al
dictado. Para volver a la app donde escribías usa el botón «◀︎» de la barra de estado:
iOS no deja a una app abrir la anterior.

Dictar requiere **Permitir acceso completo** y permiso de micrófono. Si ya tenías
una distribución guardada, la tecla Ñ no cambia: añade la acción «Dictar» a la
tecla que quieras desde el editor o restablece la distribución por defecto.

La app guarda la configuración en un App Group compartido
(`group.com.leonardoramirezr.leonerakeyboard`) y la extensión la vuelve a leer cada vez que
aparece el teclado, cuando la app que lo usa vuelve a primer plano y en cuanto la
app avisa de un cambio, así que los ajustes se aplican sin reiniciar el teclado.

## Activar el teclado

1. Instala la app.
2. Ajustes › General › Teclado › Teclados › Añadir teclado › **Leonera**.
3. Activa **Permitir acceso completo** para pegar, vibración/sonido, dictar y para
   que el teclado lea la distribución personalizada desde la app.

## Estructura

| Carpeta | Contenido |
| --- | --- |
| `Shared/` | Modelo, distribución por defecto, almacenamiento, vista de tecla, grabación y cliente de Groq (compartidos) |
| `KeyboardExtension/` | Extensión de teclado (`UIInputViewController` + SwiftUI) |
| `App/` | App contenedora: instrucciones, prueba y editor |
| `project.yml` | Definición del proyecto para [XcodeGen](https://github.com/yonaskolb/XcodeGen) |
| `scripts/adhoc.py` | Generación de las páginas de instalación |
| `scripts/asc.py` | Cliente de la API de App Store Connect (comprobación de la clave y revocación del certificado temporal) |
| `scripts/publish-pages.sh` | Publicación de cada build en la rama `gh-pages` |

El proyecto de Xcode no se guarda en el repositorio; se genera con XcodeGen
(herramienta de compilación únicamente, la app no tiene dependencias).

## Compilar

### GitHub Actions

`.github/workflows/build.yml` se ejecuta en **cada push** a cualquier rama (no en
los pull requests ni en `gh-pages`). Genera el proyecto, compila para `iphoneos`,
firma la app y publica el IPA. Ningún build se cancela: los de `main` se ejecutan
de uno en uno (para no repetir versión) y los de otras ramas en paralelo.

| Origen | Etiqueta (tag) | Publicación |
| --- | --- | --- |
| Commit en `main` (p. ej. al hacer merge) | `0.1.0`, `0.2.0`, `0.3.0`… (sube el número intermedio en cada push) | [Release](../../releases) estable, marcado como *Latest* |
| Commit en otra rama | `build-<número de ejecución>-<commit>` (p. ej. `build-7-9fb81b8`) | Pre-release |

Con firma Ad Hoc, además, cada build (de `main` y de las demás ramas) se publica en
GitHub Pages en una carpeta con el nombre de su etiqueta
(`https://<usuario>.github.io/<repositorio>/<etiqueta>/`); ver
[Instalación Ad Hoc](#instalación-ad-hoc-github-pages).

Todas las etiquetas aparecen en [Tags](../../tags) y cada una tiene el IPA
adjunto en su release: `LeoneraKeyboard-<etiqueta>-adhoc.ipa` si están configurados
los secrets de firma (ver [Instalación Ad Hoc](#instalación-ad-hoc-github-pages)) o
`LeoneraKeyboard-<etiqueta>-unsigned.ipa` si no. La versión de la app
(`CFBundleShortVersionString`) es la de la próxima release de `main`, y el número
de build es el número de ejecución del workflow.

Si un push a `main` incluye varios commits, se publica una sola release con el
último de ellos.

#### IPA sin firmar

Sin los secrets de firma, el IPA no está firmado con ningún certificado: para
instalarlo hay que firmarlo (por ejemplo con SideStore, AltStore o Sideloadly). Se
firma sin certificado (`codesign --sign -`) solo para que declare el App Group
(`com.apple.security.application-groups`): sin ello SideStore y AltStore no lo
registran. Asegúrate de que la herramienta conserve el App Group; si no, el teclado funcionará con la distribución por
defecto pero no verá los cambios hechos en la app ni la API key del dictado. Si la
herramienta cambia el nombre del App Group (AltStore y SideStore, por ejemplo,
le añaden el ID del equipo), la app y el teclado lo detectan solos a partir de
`ALTAppGroups` o del perfil de aprovisionamiento. En la app, **Dictado ›
Conexión con el teclado** indica si ambos comparten los ajustes.

### Instalación Ad Hoc (GitHub Pages)

Con una cuenta del Apple Developer Program y una clave de la API de App Store
Connect, el workflow firma el IPA Ad Hoc con la **firma automática de Xcode** y
publica **cada build** en GitHub Pages, con la misma nomenclatura que
[Tags](../../tags):

| Página | Contenido |
| --- | --- |
| `https://<usuario>.github.io/<repositorio>/` | Portada: botón para instalar la última versión estable de `main` y lista de todos los builds |
| `…/0.3.0/` | Build de `main` (release estable) |
| `…/build-7-9fb81b8/` | Build de otra rama |

Cada carpeta tiene un botón **Instalar** que, abierto en Safari desde el iPhone,
instala la app directamente (`itms-services`), además de su `manifest.plist` y el
IPA `LeoneraKeyboard-<etiqueta>-adhoc.ipa`. Solo se instala en los dispositivos
registrados en la cuenta de Apple Developer y no hace falta activar el modo de
desarrollador. El
enlace de cada build aparece también en el resumen de la ejecución en *Actions* y
en las notas de los pre-releases.

Las páginas se guardan en la rama `gh-pages` (`scripts/publish-pages.sh`), que
tiene un solo commit que se reemplaza en cada publicación para que los IPA no se
acumulen en el historial. Se conservan todas las versiones de `main` y los 50
builds de otras ramas más recientes (los anteriores siguen en su release). Si dos
builds publican a la vez, el segundo reintenta sobre la versión del primero.

En cada build, `xcodebuild -allowProvisioningUpdates` con la clave de API:

1. Registra (si no existen) los App ID de la app y del teclado con la capacidad
   **App Groups** (el grupo en sí hay que asignarlo a mano, ver abajo).
2. Archiva la app firmada con un certificado de desarrollo temporal.
3. Exporta el IPA Ad Hoc (`release-testing`): genera los perfiles Ad Hoc con
   **todos los dispositivos registrados** y firma con el certificado de
   distribución gestionado en la nube por Apple.
4. Revoca el certificado de desarrollo temporal (`scripts/asc.py`), para no
   llegar al límite de certificados de la cuenta.

Antes de compilar, `scripts/asc.py check` comprueba que la clave funcione y que
haya al menos un iPhone registrado.

| Identificador | Valor |
| --- | --- |
| App | `com.leonardoramirezr.leonerakeyboard` |
| Teclado | `com.leonardoramirezr.leonerakeyboard.extension` |
| App Group | `group.com.leonardoramirezr.leonerakeyboard` |

Son fijos: se definen en `project.yml` (`APP_BUNDLE_ID` y `APP_GROUP_ID`; el
teclado es siempre `$(APP_BUNDLE_ID).extension`) y el workflow los lee de ahí.

#### 1. Apple Developer

1. Registra el UDID de cada iPhone/iPad en
   [Certificates, Identifiers & Profiles › Devices](https://developer.apple.com/account/resources/devices/list).
2. En [App Store Connect › Users and Access › Integrations › App Store Connect
   API](https://appstoreconnect.apple.com/access/integrations/api) crea una
   **Team Key** con rol **Admin** (hace falta para el certificado de distribución
   gestionado en la nube) y descarga el `.p8` (solo se puede descargar una vez).
   Anota el **Key ID** y el **Issuer ID**.
3. **Una sola vez por app**, porque la API no permite gestionar App Groups: en
   **Identifiers › App Groups** crea `group.com.leonardoramirezr.leonerakeyboard` y asígnalo
   (*App Groups › Configure*) a los dos App ID (`com.leonardoramirezr.leonerakeyboard` y
   `com.leonardoramirezr.leonerakeyboard.extension`). Si
   los App ID aún no existen, el primer build los crea y falla avisando de este paso.
4. Copia tu **Team ID** de
   [Membership details](https://developer.apple.com/account#MembershipDetailsCard).

#### 2. Secrets

En *Settings › Secrets and variables › Actions* (del repositorio, o de la
organización si el repositorio pertenece a ella):

| Secret | Valor |
| --- | --- |
| `ASC_KEY_ID` | Key ID de la clave |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8` | Contenido completo del archivo `AuthKey_<KeyID>.p8` (o en base64) |
| `APPLE_TEAM_ID` | Team ID (10 caracteres) |

Sin ninguno se genera el IPA sin firmar; si falta alguno (pero no todos), el
workflow falla para no publicar sin firma por error. La clave tiene rol Admin:
guárdala solo como secret.

#### 3. GitHub Pages

El primer build firmado crea la rama `gh-pages`. Después, en *Settings › Pages ›
Build and deployment*, elige **Source: Deploy from a branch** y **Branch:
`gh-pages` / `(root)`**. Solo hay que hacerlo una vez.

#### 4. Instalar

Haz push a cualquier rama o merge a `main` y abre en **Safari** desde el iPhone la
portada o la carpeta del build. La portada puede tardar unos minutos en mostrar el
build nuevo por la caché de GitHub Pages; la carpeta de cada build es nueva, así
que no le afecta.

Al tener otros bundle id, la app firmada Ad Hoc se instala aparte de la que
hubieras instalado con SideStore/AltStore: exporta la configuración desde la app
anterior e impórtala en la nueva, y vuelve a escribir la API key del dictado.

#### Añadir un dispositivo

Registra el UDID en **Devices** y haz un push (o ejecuta el workflow): el perfil
Ad Hoc se regenera con todos los dispositivos registrados. Los builds anteriores
no se pueden instalar en el dispositivo nuevo.

### En local (macOS)

```sh
brew install xcodegen
xcodegen generate
open LeoneraKeyboard.xcodeproj
```

En Xcode selecciona tu equipo en *Signing & Capabilities* para ambos targets. Si
usas tu propio equipo, cambia `APP_BUNDLE_ID` y `APP_GROUP_ID` en `project.yml`.
