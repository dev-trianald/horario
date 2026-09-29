# Horario 2º DAM

Aplicación web estática para consultar el horario y guardar tareas y exámenes en Supabase. Cada persona inicia sesión con su cuenta y solo puede consultar y modificar sus propios apuntes.

## Configuración de Supabase

1. Crea un proyecto en [Supabase](https://supabase.com/).
2. En el **SQL Editor** del proyecto, ejecuta el contenido de [`supabase/schema.sql`](supabase/schema.sql). Esto crea la tabla `tasks` y sus políticas de seguridad por usuario (RLS).
   Si la tabla ya existía, ejecuta [`supabase/migration-add-week-start.sql`](supabase/migration-add-week-start.sql) y [`supabase/migration-add-completed.sql`](supabase/migration-add-completed.sql) para añadir las columnas nuevas sin borrar tus tareas.
3. En **Project Settings > API**, copia la **Project URL** y la clave pública **anon / publishable**.
4. Pega esos valores en `config.js`:

   ```js
   window.SUPABASE_CONFIG = {
	   url: "https://tu-proyecto.supabase.co",
	   anonKey: "tu-clave-publica"
   };
   ```

   La clave pública está pensada para estar en el navegador. No pongas aquí una `service_role` ni ninguna clave secreta; la protección de los datos depende de las políticas RLS del esquema.

5. Sirve la carpeta con un servidor web estático o publícala en un hosting estático. Abre la URL publicada, crea una cuenta y confirma el correo si Supabase lo solicita. No abras `index.html` directamente como archivo local.

Al pulsar una asignatura puedes añadir una tarea o examen. Los cambios se guardan en Supabase y se vuelven a cargar al iniciar sesión. La edición y el borrado también se sincronizan con la base de datos.

Al crear o editar un apunte puedes activar **Marcar como examen**. La etiqueta `EXAMEN` aparecerá por encima de la tarjeta y puedes guardarlo sin escribir detalles; en ese caso se guardará como `Examen`. También puedes guardarlo para la semana actual o elegir una fecha de otra semana.

Marca una tarea con el botón de check para moverla al **Historial** del panel lateral. Desde el historial puedes reabrirla y devolverla a pendientes.

## Sincronizar con Google Calendar

La sincronización necesita que cada usuario autorice Google Calendar con la misma dirección de correo usada para iniciar sesión en la app. Al conectar, la app solicita los permisos `calendar.events` y `userinfo.email`; verifica que ambas cuentas coincidan y usa Calendar para crear, actualizar y borrar eventos de día completo. Los eventos contienen el tipo de apunte, la asignatura, su descripción y la fecha. No se envían a Google hasta que el usuario conecta su cuenta. La política de privacidad está en [`pages/privacidad.html`](pages/privacidad.html).

1. En [Google Cloud Console](https://console.cloud.google.com/), crea o selecciona un proyecto y habilita **Google Calendar API**.
2. Configura la pantalla de consentimiento OAuth. Si la app está en modo de pruebas, añade como usuario de prueba cada cuenta que vaya a conectar Calendar.
3. Crea un **OAuth Client ID** de tipo **Web application**. Añade el dominio publicado de la app en **Authorized JavaScript origins**. Para desarrollo local, añade también el origen local que uses, por ejemplo `http://localhost:8000`.
4. Copia el ID de cliente (termina en `.apps.googleusercontent.com`) en `googleClientId` dentro de `config.js`. Este ID es público; no pegues secretos OAuth ni claves privadas en la web.
5. Publica la app y pulsa **Conectar Google Calendar** después de iniciar sesión. Google mostrará el consentimiento. La dirección de Google debe coincidir con el correo de Supabase.

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

La autenticación usa correo y contraseña de Supabase. Si tienes activada la confirmación de correo, configura también la URL de tu web en **Authentication > URL Configuration**.

## Instalarla en el móvil

Publica la carpeta en un hosting con HTTPS, por ejemplo Netlify o GitHub Pages. La aplicación incluye un manifiesto y un service worker para funcionar como PWA:

- En Android con Chrome, abre la URL publicada y elige **Instalar aplicación** o **Añadir a pantalla de inicio**.
- En iPhone con Safari, pulsa **Compartir**, después **Añadir a pantalla de inicio** y confirma.

La aplicación instalada usa la misma URL, cuenta y base de datos de Supabase que la versión del ordenador. Necesita conexión a Internet para iniciar sesión y sincronizar tareas.

## Obtener un APK para Android

GitHub Pages no genera archivos APK: publica la PWA. Para crear el APK a partir de la versión publicada:

1. Sube el proyecto a GitHub y activa **Settings > Pages > Deploy from a branch**, usando la rama `main` y la carpeta `/root`.
2. Abre la URL HTTPS que GitHub Pages te proporcione y comprueba que la aplicación funciona.
3. Entra en [PWABuilder](https://www.pwabuilder.com/), pega esa URL y pulsa **Start**.
4. Cuando termine el análisis, elige **Package for stores > Android** y descarga el paquete generado.
5. En Supabase añade la URL de GitHub Pages en **Authentication > URL Configuration** como **Site URL** y como URL de redirección si aparece esa opción.

El APK será una versión instalable de esta misma aplicación: usará la misma URL, el mismo `config.js` y la misma base de datos de Supabase. Para cambios posteriores, publica primero los cambios en GitHub Pages y vuelve a generar el paquete si quieres actualizar el APK.