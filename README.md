# Horario 2º DAM

La aplicación web y Android se compilan desde la misma app Flutter (`lib/`) y comparten Firebase Authentication y Cloud Firestore. Cada usuario solo puede consultar y modificar sus propios apuntes. La carpeta `supabase/` conserva el esquema SQL anterior únicamente como referencia: no lo ejecutes para configurar Firebase.

## Aplicación Flutter

La app Flutter está en `lib/` y guarda tareas y recordatorios en `users/{uid}/tasks` y `users/{uid}/reminders` de Firestore. El acceso admite Google y correo/contraseña. Al crear una clase puedes iniciar un horario desde cero o copiar las asignaturas y franjas de otra clase. Las tareas se pueden sincronizar opcionalmente con Google Calendar; los recordatorios sin fecha no se exportan.

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

En Linux, compilar iOS requiere macOS y Xcode; Android necesita Android Studio/SDK. La app Flutter no puede usar Firebase Authentication ni Cloud Firestore en Linux porque esos plugins no ofrecen soporte nativo para esta plataforma; para usar todas las funciones, abre la [versión web](https://horario-eba89.web.app/).

### Publicar Flutter en Firebase Hosting

El archivo `firebase.json` publica `build/web` en Firebase Hosting. Antes de conectar Calendar, añade `horario-eba89.web.app` a **Firebase Authentication > Settings > Authorized domains** y a **Authorized JavaScript origins** del cliente OAuth de Google indicado en `web/index.html`. Añade también `http://localhost` para desarrollo. Habilita Google Calendar API en el proyecto de Google Cloud y configura la pantalla de consentimiento y los usuarios de prueba.

```sh
flutter build web
firebase deploy --only hosting --project horario-eba89
```

La URL de Hosting será `https://horario-eba89.web.app`. Esta publicación sirve la misma implementación Flutter que Android. Al iniciar sesión, abre **Tu cuenta > Conectar Google Calendar**. Google pedirá permiso explícito; la app comprueba que el correo de Calendar coincide con Firebase Auth y conserva el token solo en memoria. La sincronización se pierde al recargar y requiere volver a conectar.

## Configuración y publicación de Flutter Web

Flutter Web usa el mismo modelo, servicios y colecciones Firestore que Android. El UID de Firebase Auth determina el propietario; no se guarda un `userId` adicional en cada documento. El esquema GraphQL con `@table` corresponde a Firebase Data Connect/Cloud SQL y no se usa en esta app, que utiliza Cloud Firestore.

1. En el mismo proyecto de Firebase, registra una aplicación **Web** y habilita **Authentication > Sign-in method > Email/Password**.
2. Crea la base de datos en **Firestore Database** y publica las reglas del repositorio:

   ```sh
   firebase deploy --only firestore:rules --project TU_PROJECT_ID
   ```

3. Registra Web y Android en el mismo proyecto Firebase y genera `lib/firebase_options.dart` con FlutterFire. La configuración cliente (`apiKey`, `appId`, `projectId`) no es una clave de cuenta de servicio.
4. Ejecuta `flutter pub get` y `flutter run -d chrome` para probar la versión web local. No abras el HTML directamente como archivo local.

GitHub Pages publica Flutter Web automáticamente mediante `.github/workflows/deploy-web.yml` en `https://dev-trianald.github.io/horario/`. En **Settings > Pages**, selecciona **GitHub Actions** como fuente. El workflow compila con la ruta `/horario/`; Firebase Hosting, en cambio, sirve la compilación en la raíz con `flutter build web`. Añade `dev-trianald.github.io` a **Firebase Authentication > Settings > Authorized domains** y al origen autorizado del cliente OAuth de Google. Si restringes la API key por sitios web, permite `https://dev-trianald.github.io/*` y el origen local de desarrollo.

Firebase Auth crea una sesión al registrar una cuenta y permite recuperar el acceso mediante los flujos de Firebase. El cliente OAuth web que usa Google Calendar se configura en `web/index.html`; la autenticación de la app usa Firebase Auth en ambas plataformas.

La configuración cliente de Firebase no protege por sí sola los datos: las reglas de `firestore.rules` limitan cada operación a `users/{uid}`. Los usuarios y datos que sigan en Supabase no se trasladan automáticamente; hay que migrarlos por separado. Las cuentas necesitan volver a registrarse o seguir un proceso de migración de usuarios; no copies contraseñas ni credenciales de administración al cliente.

Al pulsar una asignatura puedes añadir una tarea o examen. Los cambios se guardan en Firestore y se vuelven a cargar al iniciar sesión. La edición y el borrado también se sincronizan con la base de datos.

Al crear o editar un apunte puedes activar **Marcar como examen**. La etiqueta `EXAMEN` aparecerá por encima de la tarjeta y puedes guardarlo sin escribir detalles; en ese caso se guardará como `Examen`. También puedes guardarlo para la semana actual o elegir una fecha de otra semana.

Marca una tarea con el botón de check para moverla al **Historial** del panel lateral. Desde el historial puedes reabrirla y devolverla a pendientes.

El panel **Recordatorios** permite guardar contenido importante de una asignatura sin día ni fecha, como los temas que entran en un examen. También incluye historial, edición, completado y borrado.

## Sincronizar con Google Calendar

La sincronización necesita que cada usuario autorice Google Calendar con la misma dirección de correo usada para iniciar sesión en la app. Al conectar, la app solicita los permisos `calendar.events` y `userinfo.email`; verifica que ambas cuentas coincidan y usa Calendar para crear, actualizar y borrar eventos de día completo. Los eventos contienen el tipo de apunte, la asignatura, su descripción y la fecha. No se envían a Google hasta que el usuario conecta su cuenta. La política de privacidad está en [`web/pages/privacidad.html`](web/pages/privacidad.html).

1. En [Google Cloud Console](https://console.cloud.google.com/), crea o selecciona un proyecto y habilita **Google Calendar API**.
2. Configura la pantalla de consentimiento OAuth. Si la app está en modo de pruebas, añade como usuario de prueba cada cuenta que vaya a conectar Calendar.
3. Crea un **OAuth Client ID** de tipo **Web application**. Añade `https://dev-trianald.github.io` en **Authorized JavaScript origins** (sin la ruta `/horario/`). Para desarrollo local, añade también `http://localhost:8000`.
4. Configura el ID de cliente OAuth web (termina en `.apps.googleusercontent.com`) en `web/index.html`. Este ID es público; no pegues secretos OAuth ni claves privadas en la app.
5. Publica la app y pulsa **Conectar Google Calendar** después de iniciar sesión. Google mostrará el consentimiento. La dirección de Google debe coincidir con el correo de Firebase Auth.

La app conserva el permiso solo en memoria del navegador; puede ser necesario volver a conectar tras recargar o cerrar sesión. Al editar una tarea conectada se actualiza su evento; al eliminarla también se elimina de Google Calendar. Si Google no está conectado, la app guarda el cambio y avisa de que el calendario no se ha actualizado.

### Publicar el acceso OAuth

El código no puede cambiar el estado de publicación ni verificar el dominio por ti. Antes de poner el consentimiento OAuth a disposición de usuarios externos:

1. Despliega la app con HTTPS. Para verificar GitHub Pages, abre [Google Search Console](https://search.google.com/search-console), añade como propiedad de prefijo de URL `https://dev-trianald.github.io/horario/` y elige el método de etiqueta HTML. Copia la etiqueta exacta que Google genere dentro del `<head>` de `web/index.html`, publica el cambio y completa la verificación. No uses una etiqueta inventada: el token es único de tu cuenta.
2. En Google Auth Platform, completa **Branding** con el nombre exacto `TaskDAM`, un correo de asistencia real y las URL públicas de inicio, privacidad (`/pages/privacidad.html`) y condiciones (`/pages/terminos.html`).
3. Añade `dev-trianald.github.io` en **Authorized domains** y usa las URL HTTPS exactas de la portada y la política tanto en GitHub Pages como en la configuración OAuth. Tras verificar la propiedad, Google indica que puede tardar hasta 24 horas en actualizarse; vuelve a solicitar la revisión después.
4. Si Search Console o Google Auth Platform no aceptan el subdominio compartido de GitHub Pages como dominio de tu propiedad, configura un dominio propio en GitHub Pages y verifica ese dominio mediante DNS. Un dominio propio es necesario en ese caso; no se puede resolver cambiando solo el HTML.
5. En **Audience**, selecciona **External** y publica la app para salir del modo de prueba. Los usuarios de prueba dejan de ser la única audiencia, pero esto no sustituye una revisión de marca o permisos si Google la solicita.
6. En **Data Access**, conserva los permisos que usa el código: `https://www.googleapis.com/auth/calendar.events` y `https://www.googleapis.com/auth/userinfo.email`. Si Google exige verificar el acceso a datos, completa la solicitud indicada en **Verification Center**; no basta con marcar la app como publicada.
7. En el cliente OAuth de tipo **Web application**, añade el origen HTTPS exacto de la app en **Authorized JavaScript origins**. Actualiza también el valor `google-signin-client_id` en `web/index.html` si creas otro cliente.

Google revisa por separado la marca y los permisos de datos. Mantén accesible la web y la política durante la revisión, y usa en la consola los mismos enlaces públicos que has desplegado.

La autenticación usa Google o correo y contraseña de Firebase Authentication. Añade el dominio publicado de la web en **Authentication > Settings > Authorized domains**. Google debe estar habilitado en **Authentication > Sign-in method**.

## Instalar Flutter Web en el móvil

Publica Flutter Web con Firebase Hosting o GitHub Pages mediante el workflow del repositorio. La compilación incluye un manifiesto y un service worker para funcionar como PWA:

- En Android con Chrome, abre la URL publicada y elige **Instalar aplicación** o **Añadir a pantalla de inicio**.
- En iPhone con Safari, pulsa **Compartir**, después **Añadir a pantalla de inicio** y confirma.

La aplicación instalada usa la misma versión Flutter, cuenta y base de datos de Firebase que Android. Necesita conexión a Internet para iniciar sesión y sincronizar tareas.

## Compilar Android

Android y Flutter Web salen del mismo código. Para generar e instalar el APK:

```sh
flutter build apk --release
flutter install
```

El APK se genera en `build/app/outputs/flutter-apk/app-release.apk`. Publicar Flutter Web no actualiza un APK ya instalado: compílalo de nuevo para distribuir los cambios Android.

En cada push a la rama `Restaurar2`, GitHub Actions compila el APK y lo publica como artefacto descargable durante 90 días. Para descargarlo desde otro equipo, abre **Actions > Build Android APK**, selecciona la ejecución más reciente que haya terminado correctamente y descarga `taskdam-android-apk`.