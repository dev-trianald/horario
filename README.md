# Horario 2º DAM

La versión web estática y la aplicación Flutter usan Firebase Authentication y Cloud Firestore. Cada usuario solo puede consultar y modificar sus propios apuntes. La carpeta `supabase/` conserva el esquema SQL anterior únicamente como referencia: no lo ejecutes para configurar la versión Firebase.

## Aplicación Flutter

La app Flutter está en `lib/` y guarda tareas y recordatorios en `users/{uid}/tasks` y `users/{uid}/reminders` de Firestore. El acceso admite Google y correo/contraseña. Al crear una clase puedes iniciar un horario desde cero o copiar las asignaturas y franjas de otra clase. Incluye tareas/exámenes con semana seleccionable, completado e historial, y recordatorios con edición y borrado.

Configuración inicial:

Si el repositorio no contiene las carpetas de plataforma, genéralas fuera del proyecto y copia solo esas carpetas para no reemplazar `lib/` ni `pubspec.yaml`:

```sh
flutter create --project-name taskdam --org es.taskdam --platforms=android,ios,web /tmp/taskdam-platforms
cp -an /tmp/taskdam-platforms/android /tmp/taskdam-platforms/ios /tmp/taskdam-platforms/web .
```

1. Crea un proyecto en [Firebase Console](https://console.firebase.google.com/).
2. En **Authentication > Sign-in method**, habilita **Email/Password** y **Google**. En Google, configura el correo de asistencia del proyecto.
3. Crea una base de datos en **Firestore Database**.
4. Instala y autentica Firebase CLI y FlutterFire CLI:

   ```sh
   npm install -g firebase-tools
   firebase login
   dart pub global activate flutterfire_cli
   ```

5. Desde la raíz del repositorio, registra las plataformas y genera `lib/firebase_options.dart`:

   ```sh
   flutterfire configure --project TU_PROJECT_ID --platforms web,android,ios
   ```

   El comando configura los proyectos nativos y reemplaza la plantilla de opciones incluida. Para Android, registra también la huella SHA-1 de la app en Firebase y vuelve a descargar la configuración nativa; para web, añade el dominio de publicación a los dominios autorizados de Authentication.
6. Publica las reglas de seguridad de `firestore.rules`:

   ```sh
   firebase deploy --only firestore:rules --project TU_PROJECT_ID
   ```

7. Instala dependencias y ejecuta la app:

   ```sh
   flutter pub get
   flutter run -d chrome
   ```

   Para Android/iOS, conecta un dispositivo o inicia un emulador y ejecuta `flutter run`.

No pongas credenciales de cuentas de servicio en la app. La seguridad depende de Firebase Authentication y las reglas de Firestore. Los usuarios y apuntes que ya están en Supabase permanecen allí; hay que crear las cuentas de nuevo en Firebase y exportar/importar los apuntes por separado si quieres conservarlos.

En Linux, compilar iOS requiere macOS y Xcode; Android necesita Android Studio/SDK. La sincronización con Google Calendar de la versión web aún no está portada a Flutter.

## Configuración de Firebase para la web

La web guarda los datos en `users/{uid}/tasks/{taskId}` y `users/{uid}/reminders/{reminderId}`. El UID de Firebase Auth determina el propietario; no se guarda un `userId` adicional en cada documento. El esquema GraphQL con `@table` corresponde a Firebase Data Connect/Cloud SQL y no se usa en esta app, que utiliza Cloud Firestore.

1. En el mismo proyecto de Firebase, registra una aplicación **Web** y habilita **Authentication > Sign-in method > Email/Password**.
2. Crea la base de datos en **Firestore Database** y publica las reglas del repositorio:

   ```sh
   firebase deploy --only firestore:rules --project TU_PROJECT_ID
   ```

3. Copia la configuración de la aplicación web que muestra Firebase y rellena `firebase` en `config.js` (`apiKey`, `authDomain`, `projectId`, `appId` y `messagingSenderId`). Son valores de configuración pública; no pongas claves de cuentas de servicio ni secretos en el navegador.
4. Para usar la versión Flutter, ejecuta también `flutterfire configure --project TU_PROJECT_ID --platforms web,android,ios`; esto genera `lib/firebase_options.dart`. El archivo actual es una plantilla sin configuración.
5. Sirve la carpeta con un servidor web estático o publícala en un hosting estático. No abras `index.html` directamente como archivo local.

Para publicar en GitHub Pages en `https://dev-trianald.github.io/horario/`, añade `dev-trianald.github.io` a **Firebase Authentication > Settings > Authorized domains**. Si restringes la API key por sitios web, permite `https://dev-trianald.github.io/*` y el origen local de desarrollo. En el cliente OAuth de Google, el origen autorizado es `https://dev-trianald.github.io` (sin `/horario/`); el origen local `http://localhost:8000` se añade por separado.

Firebase Auth crea una sesión al registrar una cuenta y permite recuperar el acceso mediante los flujos de Firebase. Para iniciar sesión con Google u otro proveedor habrá que habilitarlo en Firebase Authentication y añadir el botón y el flujo correspondiente. El OAuth de Google Calendar es independiente y se configura con `googleClientId` en `config.js`.

La configuración cliente de Firebase no protege por sí sola los datos: las reglas de `firestore.rules` limitan cada operación a `users/{uid}`. Los usuarios y datos que sigan en Supabase no se trasladan automáticamente; hay que migrarlos por separado. Las cuentas necesitan volver a registrarse o seguir un proceso de migración de usuarios; no copies contraseñas ni credenciales de administración al cliente.

Al pulsar una asignatura puedes añadir una tarea o examen. Los cambios se guardan en Firestore y se vuelven a cargar al iniciar sesión. La edición y el borrado también se sincronizan con la base de datos.

Al crear o editar un apunte puedes activar **Marcar como examen**. La etiqueta `EXAMEN` aparecerá por encima de la tarjeta y puedes guardarlo sin escribir detalles; en ese caso se guardará como `Examen`. También puedes guardarlo para la semana actual o elegir una fecha de otra semana.

Marca una tarea con el botón de check para moverla al **Historial** del panel lateral. Desde el historial puedes reabrirla y devolverla a pendientes.

El panel **Recordatorios** permite guardar contenido importante de una asignatura sin día ni fecha, como los temas que entran en un examen. También incluye historial, edición, completado y borrado.

## Sincronizar con Google Calendar

La sincronización necesita que cada usuario autorice Google Calendar con la misma dirección de correo usada para iniciar sesión en la app. Al conectar, la app solicita los permisos `calendar.events` y `userinfo.email`; verifica que ambas cuentas coincidan y usa Calendar para crear, actualizar y borrar eventos de día completo. Los eventos contienen el tipo de apunte, la asignatura, su descripción y la fecha. No se envían a Google hasta que el usuario conecta su cuenta. La política de privacidad está en [`pages/privacidad.html`](pages/privacidad.html).

1. En [Google Cloud Console](https://console.cloud.google.com/), crea o selecciona un proyecto y habilita **Google Calendar API**.
2. Configura la pantalla de consentimiento OAuth. Si la app está en modo de pruebas, añade como usuario de prueba cada cuenta que vaya a conectar Calendar.
3. Crea un **OAuth Client ID** de tipo **Web application**. Añade `https://dev-trianald.github.io` en **Authorized JavaScript origins** (sin la ruta `/horario/`). Para desarrollo local, añade también `http://localhost:8000`.
4. Copia el ID de cliente (termina en `.apps.googleusercontent.com`) en `googleClientId` dentro de `config.js`. Este ID es público; no pegues secretos OAuth ni claves privadas en la web.
5. Publica la app y pulsa **Conectar Google Calendar** después de iniciar sesión. Google mostrará el consentimiento. La dirección de Google debe coincidir con el correo de Firebase Auth.

La app conserva el permiso solo en memoria del navegador; puede ser necesario volver a conectar tras recargar o cerrar sesión. Al editar una tarea conectada se actualiza su evento; al eliminarla también se elimina de Google Calendar. Si Google no está conectado, la app guarda el cambio y avisa de que el calendario no se ha actualizado.

### Publicar el acceso OAuth

El código no puede cambiar el estado de publicación ni verificar el dominio por ti. Antes de poner el consentimiento OAuth a disposición de usuarios externos:

1. Despliega la app con HTTPS. Para verificar GitHub Pages, abre [Google Search Console](https://search.google.com/search-console), añade como propiedad de prefijo de URL `https://dev-trianald.github.io/horario/` y elige el método de etiqueta HTML. Copia la etiqueta exacta que Google genere dentro del `<head>` de `index.html`, publica el cambio y completa la verificación. No uses una etiqueta inventada: el token es único de tu cuenta.
2. En Google Auth Platform, completa **Branding** con el nombre exacto `TaskDAM`, un correo de asistencia real y las URL públicas de inicio, privacidad (`/pages/privacidad.html`) y condiciones (`/pages/terminos.html`). La portada identifica TaskDAM, describe su función y enlaza la política.
3. Añade `dev-trianald.github.io` en **Authorized domains** y usa las URL HTTPS exactas de la portada y la política tanto en GitHub Pages como en la configuración OAuth. Tras verificar la propiedad, Google indica que puede tardar hasta 24 horas en actualizarse; vuelve a solicitar la revisión después.
4. Si Search Console o Google Auth Platform no aceptan el subdominio compartido de GitHub Pages como dominio de tu propiedad, configura un dominio propio en GitHub Pages y verifica ese dominio mediante DNS. Un dominio propio es necesario en ese caso; no se puede resolver cambiando solo el HTML.
5. En **Audience**, selecciona **External** y publica la app para salir del modo de prueba. Los usuarios de prueba dejan de ser la única audiencia, pero esto no sustituye una revisión de marca o permisos si Google la solicita.
6. En **Data Access**, conserva los permisos que usa el código: `https://www.googleapis.com/auth/calendar.events` y `https://www.googleapis.com/auth/userinfo.email`. Si Google exige verificar el acceso a datos, completa la solicitud indicada en **Verification Center**; no basta con marcar la app como publicada.
7. En el cliente OAuth de tipo **Web application**, añade el origen HTTPS exacto de la app en **Authorized JavaScript origins**. Actualiza también `googleClientId` en `config.js` si creas otro cliente.

Google revisa por separado la marca y los permisos de datos. Mantén accesible la web y la política durante la revisión, y usa en la consola los mismos enlaces públicos que has desplegado.

La autenticación usa Google o correo y contraseña de Firebase Authentication. Añade el dominio publicado de la web en **Authentication > Settings > Authorized domains**. Google debe estar habilitado en **Authentication > Sign-in method**.

## Instalarla en el móvil

Publica la carpeta en un hosting con HTTPS, por ejemplo Netlify o GitHub Pages. La aplicación incluye un manifiesto y un service worker para funcionar como PWA:

- En Android con Chrome, abre la URL publicada y elige **Instalar aplicación** o **Añadir a pantalla de inicio**.
- En iPhone con Safari, pulsa **Compartir**, después **Añadir a pantalla de inicio** y confirma.

La aplicación instalada usa la misma URL, cuenta y base de datos de Firebase que la versión del ordenador. Necesita conexión a Internet para iniciar sesión y sincronizar tareas.

## Obtener un APK para Android

GitHub Pages no genera archivos APK: publica la PWA. Para crear el APK a partir de la versión publicada:

1. Sube el proyecto a GitHub y activa **Settings > Pages > Deploy from a branch**, usando la rama `main` y la carpeta `/root`.
2. Abre la URL HTTPS que GitHub Pages te proporcione y comprueba que la aplicación funciona.
3. Entra en [PWABuilder](https://www.pwabuilder.com/), pega esa URL y pulsa **Start**.
4. Cuando termine el análisis, elige **Package for stores > Android** y descarga el paquete generado.
5. En Firebase Authentication comprueba que el dominio de GitHub Pages esté incluido en **Authorized domains**.

El APK será una versión instalable de esta misma aplicación: usará la misma URL, el mismo `config.js` y la misma base de datos de Firebase. Para cambios posteriores, publica primero los cambios en GitHub Pages y vuelve a generar el paquete si quieres actualizar el paquete.