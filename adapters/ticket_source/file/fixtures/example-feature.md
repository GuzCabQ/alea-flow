# Pantalla de historial de compras del usuario

## Descripción

Construir una nueva sección en el perfil del usuario donde pueda ver su historial de compras pasadas. La pantalla debe mostrar una lista paginada de pedidos, cada uno con la fecha, el monto total y un estado (entregado / cancelado / en camino). Al tocar un pedido, navegar al detalle de ese pedido (pantalla ya existente).

Diseño aprobado por producto: https://www.figma.com/design/abc123XYZ/Purchase-History?node-id=42-1234

El endpoint de backend ya está listo: `GET /api/users/{id}/orders?page={n}&size=20`. Devuelve `{ orders: [...], total: N, page: N }`.

## Criterios de aceptación

- El usuario puede acceder a "Historial" desde su perfil
- Se muestran los pedidos paginados de 20 en 20
- Cada pedido muestra fecha (formato `dd/MM/yyyy`), monto total con símbolo de moneda, y estado con color (verde/rojo/amarillo)
- Al tocar un pedido, navegar a `/orders/{id}` con la información cargada
- En estado de carga inicial se muestra un skeleton
- Si la lista está vacía, mostrar `EmptyState` con mensaje "Aún no tienes pedidos"
- Si el endpoint falla, mostrar `ErrorMessage` con botón "Reintentar"

## Adjuntos

- [Diseño Figma](https://www.figma.com/design/abc123XYZ/Purchase-History?node-id=42-1234)
- [Mockup del estado vacío](./mocks/empty-state.png)

## Prioridad

high

## Etiquetas

- feature
- profile
- orders
