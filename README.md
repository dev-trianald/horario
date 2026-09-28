# Horario 2º DAM

Aplicación web estática para consultar el horario y guardar tareas y exámenes en Supabase. Cada persona inicia sesión con su cuenta y solo puede consultar y modificar sus propios apuntes.

## Configuración de Supabase

1. Crea un proyecto en [Supabase](https://supabase.com/).
2. En el **SQL Editor** del proyecto, ejecuta el contenido de [`supabase/schema.sql`](supabase/schema.sql). Esto crea la tabla `tasks` y sus políticas de seguridad por usuario (RLS).
   Si la tabla ya existía, ejecuta en su lugar [`supabase/migration-add-week-start.sql`](supabase/migration-add-week-start.sql) para añadir la selección de semanas sin borrar tus tareas.
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