# SyncroChiloe-ProyectoWeb

# 🚛 SincroChiloé

### Plataforma de Matching Logístico para Chiloé

> Conectamos camiones disponibles con cargas disponibles para reducir viajes vacíos, optimizar costos y mejorar la eficiencia del transporte en Chiloé.

---

## 📌 Descripción

**SincroChiloé** es una plataforma web orientada a optimizar el transporte de carga en Chiloé mediante un sistema de **matching entre transportistas y empresas que necesitan transportar mercancías**.

La problemática principal que buscamos resolver son los **viajes de retorno vacíos**. Muchos camiones realizan una entrega y regresan sin carga, generando pérdidas económicas asociadas al combustible, peajes y tiempo de operación, especialmente en rutas que involucran el tramo **Pargua–Chacao**.

Actualmente, gran parte de la coordinación de estos servicios se realiza mediante **WhatsApp, llamadas telefónicas y contactos directos**, lo que dificulta encontrar rápidamente una carga compatible.

SincroChiloé busca centralizar y automatizar este proceso.

---

## 🎯 Problema

Actualmente existen tres problemas principales:

* 🚚 **Camiones que regresan vacíos** después de realizar una entrega.
* 💰 **Pérdidas económicas** por combustible, tiempo y peajes.
* 📱 **Coordinación manual** mediante WhatsApp y llamadas telefónicas.

Esto genera una oportunidad para conectar la **capacidad disponible de los transportistas** con la **demanda de transporte existente**.

---

## 💡 Solución

SincroChiloé permitirá que transportistas y empresas publiquen sus necesidades de transporte y encuentren coincidencias de manera rápida.

El sistema buscará realizar un **matching automático** considerando principalmente:

* 📍 Ruta
* 📅 Fecha
* 🚛 Tipo de vehículo
* ⚖️ Tonelaje / capacidad disponible

Una vez encontrado un match, los usuarios podrán establecer contacto directamente mediante **WhatsApp o llamada telefónica**.

### Elevator Pitch

> Para transportistas y empresas de carga en Chiloé que sufren por los altos costos de retornos vacíos y peajes en Pargua–Chacao, **SincroChiloé** es una plataforma de matching operativo que conecta camiones con capacidad ociosa con cargas disponibles según ruta y tipo de vehículo.
>
> A diferencia de grupos de WhatsApp informales o llamadas manuales, nuestro producto busca automatizar el emparejamiento, generar confianza entre los participantes y optimizar el margen obtenido por cada kilómetro recorrido.

---

## 👥 Usuarios

### 🚛 Transportistas

**Luis Barría — 48 años**

Dueño de una empresa con 6 camiones.

**Problema:**

> "Estoy perdiendo dinero."

**Objetivo:**

> "Gané más dinero."

---

### 📦 Empresas de carga

**Camila Soto — 35 años**

Encargada de logística en una empresa salmonera.

**Problema:**

> "Tengo que encontrar transporte rápido."

**Objetivo:**

> "Funcionó bien."

---

### 🚚 Choferes independientes

**Rodrigo Cárdenas — 41 años**

Transportista independiente que busca evitar regresar sin carga.

**Problema:**

> "No quiero volver vacío."

**Objetivo:**

> "No perdí plata esta vez."

---

### 🛠️ Administrador

**José Guanel — 22 años**

Responsable de administrar y monitorear la plataforma.

Sus principales responsabilidades serán:

* Gestionar usuarios.
* Monitorear publicaciones.
* Detectar errores.
* Supervisar matches.
* Mantener el correcto funcionamiento de la plataforma.

---

## ⭐ Propuesta de Valor

### MVP — Must Have

El producto mínimo viable contempla:

* [ ] Publicación de cargas.
* [ ] Publicación de espacio/capacidad disponible.
* [ ] Matching básico por ruta.
* [ ] Matching por fecha.
* [ ] Matching por tonelaje.
* [ ] Contacto directo mediante WhatsApp o llamada.
* [ ] Notificaciones en tiempo real.
* [ ] Sistema de ratings y reputación.

### 🚀 Futuras funcionalidades

Estas funcionalidades podrán incorporarse posteriormente:

* [ ] Multicarga para optimizar la capacidad de un camión.
* [ ] Precios referenciales.
* [ ] Seguimiento de envíos.
* [ ] Mejoras en el algoritmo de matching.
* [ ] Geolocalización.
* [ ] Funcionalidad offline con sincronización.

---

## 💰 Modelo de Negocio

El modelo inicial considera:

**Fuente principal de ingresos**

* Comisión por cada viaje realizado mediante la plataforma.

**Futuras fuentes de ingresos**

* Servicios premium.
* Funcionalidades avanzadas para empresas.
* Herramientas adicionales para transportistas.

### Canales

* 🌐 Plataforma web.
* 📱 Aplicación móvil.
* 📲 Redes sociales.
* 🤝 Sindicatos y organizaciones de transportistas.

### Competencia actual

La principal alternativa actualmente son:

* Grupos de WhatsApp.
* Llamadas telefónicas.
* Contactos personales.
* Coordinación directa entre empresas y transportistas.

### Diferenciación

SincroChiloé busca diferenciarse mediante:

**Automatización + seguridad + eficiencia + reputación**

---

## 🗺️ Roadmap

### Mes 1 — Diseño y fundamentos

* Diseño UX/UI.
* Validación del modelo de datos.
* Diseño y validación de la base de datos.
* Definición de arquitectura.
* Preparación del proyecto web.

### Mes 2 — Desarrollo del MVP

* Sistema de publicaciones.
* Panel de usuarios.
* Algoritmo inicial de matching.
* Gestión de cargas y vehículos.
* Sistema de contacto.

### Mes 3 — Piloto

Realizar un piloto enfocado inicialmente en las rutas:

**Quellón → Castro → Ancud → Pargua**

Objetivo:

> Validar el funcionamiento del sistema con usuarios reales y obtener retroalimentación para futuras iteraciones.

---

## ⚠️ Riesgos

| Riesgo                      | Estrategia de mitigación                          |
| --------------------------- | ------------------------------------------------- |
| Baja adopción               | Realizar pilotos con sindicatos y transportistas  |
| Desintermediación           | Sistema de ratings y generación de valor continuo |
| Desconfianza entre usuarios | Validación de usuarios y sistema de reputación    |
| Problemas de conectividad   | Diseñar soporte offline y sincronización          |

---

## 🏗️ Arquitectura del Proyecto

Este repositorio corresponde al **desarrollo de la plataforma web de SincroChiloé**.

La arquitectura y tecnologías definitivas serán definidas durante la etapa de desarrollo.

### Estado actual

> 🟡 **Etapa de planificación y diseño**

Actualmente el proyecto cuenta con:

* ✅ Visión del producto.
* ✅ Definición del problema.
* ✅ Propuesta de valor.
* ✅ Historias de usuario.
* ✅ Modelo relacional.
* ✅ Base de datos inicial.
* 🚧 Desarrollo de la plataforma web.
* ⏳ Algoritmo de matching.
* ⏳ Pruebas con usuarios.

---

## 📂 Repositorios

El proyecto será dividido por plataforma para mantener una arquitectura y ciclo de desarrollo independientes.

### 🌐 SincroChiloé Web

**Este repositorio**

Contendrá el desarrollo de la plataforma web.

### 📱 SincroChiloé Mobile

**Repositorio futuro**

Contendrá el desarrollo de la aplicación móvil.

---

## 👨‍💻 Equipo

| Rol                    | Integrante       |
| ---------------------- | ---------------- |
| Product Owner          | Empresa Digitala |
| Fullstack / Desarrollo | José             |
| Fullstack / Desarrollo | Benjamín         |
| UX/UI                  | Vicente          |
| UX/UI                  | Francisco        |

---

## 📚 Metodologías y herramientas

El desarrollo del proyecto está basado en principios de:

* **Agile Inception**
* **Product Vision Board**
* **Customer Journey Maps**
* **SCAMPER**
* **Historias de Usuario**
* **Modelo Relacional**

Estas herramientas permiten definir y validar progresivamente el producto antes y durante su implementación.

---

## 🎯 Visión

> **Reducir los viajes vacíos en Chiloé, aumentar la eficiencia del transporte y generar nuevas oportunidades de ingresos mediante un sistema de matching logístico en tiempo real.**

---

## 🚧 Estado del proyecto

**SincroChiloé se encuentra actualmente en etapa de planificación y desarrollo inicial.**

Este repositorio evolucionará progresivamente desde la arquitectura y configuración inicial hasta convertirse en la plataforma web funcional del proyecto.

---

### SincroChiloé

**Conectando rutas. Optimizando viajes. Sincronizando Chiloé.** 🚛🌊
