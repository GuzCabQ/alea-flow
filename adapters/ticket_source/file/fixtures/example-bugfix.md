# El monto de la venta no se actualiza al cambiar la cantidad

## Descripción

En la pantalla de checkout, cuando el usuario modifica la cantidad de un producto en el carrito usando los botones `+` / `-`, el subtotal del producto se actualiza pero el total general de la venta NO se recalcula. El total sigue mostrando el valor inicial hasta que el usuario sale y vuelve a entrar a la pantalla.

Reportado por QA en sesión del 2026-05-10. Reproducible al 100% con cualquier producto.

Comportamiento esperado: el total general debe recalcularse en tiempo real cada vez que cambia la cantidad de cualquier producto del carrito.

## Criterios de aceptación

- Al tocar `+` o `-` en cualquier producto, el subtotal de ese producto y el total general se actualizan inmediatamente
- El total nunca queda fuera de sincronía con la suma de subtotales
- Funciona con productos con descuento aplicado

## Prioridad

high

## Etiquetas

- bug
- checkout
- regression
