# AutoRim (Vue 3 + Bootstrap 5 + Express + MySQL)

## Puesta en marcha
1. Importar en MySQL (phpMyAdmin → Importar), en este orden: `autorim.sql` (estructura), `autorim_insert.sql` (datos de prueba, opcional) y `database/autorim_pagos.sql` (tabla de pagos).
2. Copiar `.env.example` como `.env` y completar `DB_PASSWORD` (si tiene) y `JWT_SECRET`.
3. Instalar y arrancar:

       npm install
       npm run dev        # web en http://localhost:5173 + API en http://127.0.0.1:3001

4. Crear el administrador (opción rápida con XAMPP: importar `database/autorim_admin.sql` en phpMyAdmin; datos dentro del archivo). O por comando (el código y la clave se guardan con hash en MB_DG_USUARIOS):

       npm run crear-admin -- admin@autorim.com "UnaClaveSegura1" "CODIGO-DE-ACCESO"

## Panel de administración (/#/admin)
- **Pedidos:** resumen y listado (vistas de MySQL).
- **Tablas (CRUD):** insertar, consultar (con búsqueda y paginación), actualizar y eliminar en las 11 tablas del modelo
  (usuarios, autos, colores, acabados, rines, llantas, medidas, configuraciones, pedidos, renglones y pagos).
  Las llaves foráneas se eligen en listas; las contraseñas se guardan con hash. Cada cambio queda en la auditoría con el usuario que lo hizo.
- **Auditoría:** reporte de `MB_DG_AUDITORIA` filtrable por rango de fechas, tabla y operación, con resumen por día,
  detalle antes/después, exportación a CSV e impresión. La tabla de auditoría es de solo lectura (los triggers lo impiden).
- Pruebas de la lógica del CRUD (no necesitan base de datos): `npm test`.

## Cómo está conectado
- `server/index.js`: API (catálogo, registro/login, pedidos, panel admin). Todo con consultas parametrizadas.
- El catálogo (autos, colores, acabados, rines, llantas, medidas) se carga de MySQL al abrir la web (`src/store.js`).
- El carrito vive en el navegador; al pagar se guardan MB_DG_CONFIGURACIONES, MB_DG_PEDIDOS y MB_DG_PEDIDO_ITEMS en una transacción.
  El servidor recalcula nombre, detalle y precio desde la base: el navegador solo envía ids.
- Los triggers de auditoría reciben el usuario con `SET @app_usuario_id`.
- Pagos: tabla `MB_DG_PAGOS`, se guarda en la misma transacción que el pedido (con auditoría). La pasarela es simulada (aprueba siempre);
  para una real, cambia el INSERT en `server/index.js`. Solo se guarda marca y últimos 4 dígitos; nunca número completo ni CVV.
- Usuarios de prueba del insert: cualquier correo `@example.com` con la clave `Cliente123`.

## Backends (Node y Python)
Ambos exponen la misma API en `:3001` y comparten `.env`, base de datos, JWT y hashes bcrypt.
- Node: `npm install && npm test && npm run dev:api`
- Python: `cd backend-python && pip install -r requirements.txt && pytest && python app.py`
