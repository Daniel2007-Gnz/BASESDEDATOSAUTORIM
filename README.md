# AutoRim (Vue 3 + Bootstrap 5 + Express + MySQL)

## Puesta en marcha (con XAMPP)
1. Abre el panel de XAMPP y pulsa **Start** en **MySQL**. Apache solo hace falta si quieres abrir phpMyAdmin.
2. En `http://localhost/phpmyadmin` ve a **Importar** (sin seleccionar ninguna base) y sube estos archivos, en este orden:
   1. `autorim.sql` (estructura; crea la base `autorim`)
   2. `autorim_insert.sql` (datos de prueba)
   3. `database/autorim_pagos.sql` (tabla de pagos)
   4. `database/autorim_admin.sql` (administrador inicial)
3. Copia `.env.example` como `.env` y completa los datos. Con XAMPP por defecto queda así:

       DB_HOST=127.0.0.1
       DB_PORT=3306
       DB_USER=root
       DB_PASSWORD=
       DB_NAME=autorim
       JWT_SECRET=una-frase-secreta-de-mas-de-16-caracteres

4. Instala y arranca:

       npm install
       npm run dev        # web en http://localhost:5173 + API en http://127.0.0.1:3001

## Acceso de administrador

El archivo `database/autorim_admin.sql` crea este administrador:

| Dato              | Valor               |
|-------------------|---------------------|
| Correo            | `admin@autorim.com` |
| Contraseña        | `Admin12345`        |
| Código de acceso  | `AUTORIM-2026`      |

> **Importante:** son datos de demostración para desarrollo. Cámbialos antes de publicar la web.

**Cómo entrar:**
1. Abre `http://localhost:5173` y pulsa **Ingresar**.
2. Escribe el correo y la contraseña del administrador. Te lleva a `/#/admin`.
3. En el formulario "Acceso de personal" escribe la contraseña y el **código de acceso** (`AUTORIM-2026`) y pulsa **Ingresar como administrador**.
4. Desde ese momento aparece el enlace **Panel de administración** en la barra de navegación. También puedes entrar con "Acceso personal" en el pie de página.

El botón **Salir** de la barra cierra la sesión de administrador y el enlace desaparece. Un cliente normal nunca ve ese enlace.

**Comprobar qué administradores existen en la base de datos** (solo muestra correos, nunca contraseñas):

    npm run ver-admins

También puedes consultarlo en phpMyAdmin:

    SELECT id, email FROM MB_DG_USUARIOS WHERE rol = 'admin';

**Crear un administrador propio o cambiar la clave y el código** (la contraseña debe tener al menos 8 caracteres):

    npm run crear-admin -- tucorreo@dominio.com "TuClaveSegura1" "TU-CODIGO-DE-ACCESO"

Si ya existe ese correo, se actualizan su contraseña y su código. Las contraseñas y los códigos se guardan cifrados (bcrypt) y no se pueden leer; si se olvidan, se restablecen con el mismo comando.

## Usuarios de prueba
Los clientes de demostración son `cliente1@demo.com`, `cliente2@demo.com` y `cliente3@demo.com`, todos con la clave `Cliente123`. No tienen acceso al panel de administración.

## Panel de administración (/#/admin)
- **Pedidos:** resumen y listado (vistas de MySQL).
- **Reportes:** usuarios, compradores y ventas mensuales por producto.
- **Tablas (CRUD):** insertar, consultar (con búsqueda y paginación), actualizar y eliminar en las 11 tablas del modelo
  (usuarios, autos, colores, acabados, rines, llantas, medidas, configuraciones, pedidos, renglones y pagos).
  Las llaves foráneas se eligen en listas; las contraseñas se guardan con hash. Cada cambio queda en la auditoría con el usuario que lo hizo.
- **Auditoría:** reporte de `MB_DG_AUDITORIA` filtrable por rango de fechas, tabla y operación, con resumen por día,
  detalle antes/después, exportación a CSV e impresión. La tabla de auditoría es de solo lectura (los triggers lo impiden).
- Pruebas de la lógica del CRUD (no necesitan base de datos): `npm test`.

## Seguridad del acceso de administrador
- El login normal (`/api/auth/login`) siempre entrega un token de cliente, aunque la cuenta sea de administrador. Solo devuelve el rol para que la web sepa a dónde redirigir.
- Únicamente `/api/auth/admin-login` (correo + contraseña + código de acceso) entrega el token de administrador (8 horas), y es el único que aceptan las rutas `/api/admin/*`.
- Mostrar el enlace "Panel de administración" en la barra es solo una comodidad de navegación: no da permisos.
- Máximo 8 intentos fallidos de inicio de sesión cada 15 minutos por IP.

## Cómo está conectado
- `server/index.js`: API (catálogo, registro/login, pedidos, panel admin). Todo con consultas parametrizadas.
- El catálogo (autos, colores, acabados, rines, llantas, medidas) se carga de MySQL al abrir la web (`src/store.js`).
- El carrito vive en el navegador; al pagar se guardan MB_DG_CONFIGURACIONES, MB_DG_PEDIDOS y MB_DG_PEDIDO_ITEMS en una transacción.
  El servidor recalcula nombre, detalle y precio desde la base: el navegador solo envía ids.
- Los triggers de auditoría reciben el usuario con `SET @app_usuario_id`.
- Pagos: tabla `MB_DG_PAGOS`, se guarda en la misma transacción que el pedido (con auditoría). La pasarela es simulada (aprueba siempre);
  para una real, cambia el INSERT en `server/index.js`. Solo se guarda marca y últimos 4 dígitos; nunca número completo ni CVV.

## Backends (Node y Python)
Ambos exponen la misma API en `:3001` y comparten `.env`, base de datos, JWT y hashes bcrypt. Usa solo uno a la vez.
- Node: `npm install && npm test && npm run dev:api`
- Python: `cd backend-python && pip install -r requirements.txt && pytest && python app.py`
  (crear admin: `python crear_admin.py correo "clave" "codigo"`; `ver-admins` existe solo en Node).

## Problemas frecuentes
- **"No se pudo cargar el catálogo":** MySQL no está iniciado en XAMPP o la API no está corriendo. Revisa que `npm run dev` esté activo.
- **Error por `JWT_SECRET`:** falta crearlo en `.env` (mínimo 16 caracteres).
- **"Correo, contraseña o código incorrectos":** revisa los tres datos, o corre `npm run ver-admins`. Si no aparece el administrador, importa de nuevo `database/autorim_admin.sql`.
- **"Demasiados intentos":** espera unos minutos; el límite es por IP.