# ALEA — Walkthrough visual

> Compañero visual de la documentación existente. **No duplica prosa**: cada sección apunta al archivo canónico y añade el diagrama o tabla que ese archivo no tiene.

---

## 0. Cómo usar este documento

Lee los diagramas de este archivo **mientras** lees los docs de prosa que se referencian. Cada diagrama está pensado para responder una pregunta concreta:

| Pregunta | Sección | Doc complementario |
|---|---|---|
| ¿Qué es ALEA y qué problema resuelve? | [§1](#1-contexto-de-1-minuto) | [../README.md](../README.md) |
| ¿Cómo está organizado el código? | [§2](#2-mapa-del-paquete) | [../README.md#project-layout](../README.md) |
| ¿Cuál es la arquitectura? | [§3](#3-arquitectura-ports--adapters) | [../ARCHITECTURE.md](../ARCHITECTURE.md) |
| ¿Cómo fluye una corrida de ticket → MR? | [§4](#4-secuencia-de-una-corrida-completa) | [../core/commands/aflow-pipeline.md](../core/commands/aflow-pipeline.md) |
| ¿Cómo se elige un adapter en runtime? | [§5](#5-selección-de-adapters-en-runtime) | [../ARCHITECTURE.md#patterns](../ARCHITECTURE.md) |
| ¿Qué artefactos produce cada comando? | [§6](#6-flujo-de-artefactos) | [../ARCHITECTURE.md#module-responsibilities](../ARCHITECTURE.md) |
| ¿Qué hace cada subcomando del CLI? | [§7](#7-mapa-del-cli) | [../README.md#3--run-a-subcommand](../README.md) |
| ¿Cómo adopto ALEA en un proyecto? | [§8](#8-onboarding-de-un-consumer) | [CONSUMER_INTEGRATION.md](CONSUMER_INTEGRATION.md) |
| ¿Por qué se tomó cada decisión clave? | [§9](#9-decisiones-clave-adrs) | [adr/](adr/) |

---

## 1. Contexto de 1 minuto

ALEA es un **paquete Dart distribuible** que orquesta el flujo **ticket → merge request** para cualquier proyecto Flutter consumidor. Todo lo específico del proyecto vive en un único archivo `.alea.yaml` en la raíz del consumer; todo lo reutilizable vive en este paquete.

```mermaid
flowchart LR
    T[Ticket<br/>Asana / Linear / file] --> A[/aflow-analyze-ticket/]
    D[Design<br/>Figma / image / markup] --> DF[/aflow-design-feature/]
    A --> DF
    DF --> I[/implement-*/]
    I --> G[/aflow-run-gates/]
    G --> R[/aflow-review-feature/]
    R --> MR[/aflow-create-mr/]
    MR --> QA[/aflow-qa-handoff/]

    style T fill:#E0F5F5
    style D fill:#E0F5F5
    style MR fill:#FCEDF6
    style QA fill:#FCEDF6
```

Cada caja en la fila central es un **slash command** documentado en [../core/commands/](../core/commands/). La línea recta no es opcional: cada comando lee artefactos JSON/YAML escritos por el comando anterior, persistidos en `.pipeline/runs/<ticket_id>/` dentro del working tree del consumer.

**Comienza por:** [../README.md](../README.md) (10 minutos de lectura — explica qué es, status v0.1.0, quickstart).

---

## 2. Mapa del paquete

```mermaid
flowchart TB
    subgraph entry[Entry points]
        bin[bin/aflow.dart<br/>thin CLI shim, 22 LOC]
    end

    subgraph cli[CLI layer · lib/src/cli/]
        runner[cli_runner.dart<br/>CommandRunner]
        cmd[commands/<br/>analyze · match · scaffold<br/>inventory · journal · context]
    end

    subgraph services[Services · puros]
        match[matching/<br/>ΔE CIE2000, Jaccard]
        resolve[resolvers/<br/>palette, type_scale, layout]
        inv[inventory/<br/>widget builder, SymbolDigest]
        scaf[scaffolding/<br/>template_engine, executor]
        core[core/<br/>config, journal, registry, runner]
    end

    subgraph contracts_layer[Contracts · API estable]
        contracts[contracts/<br/>Analyzer, Adapter<br/>ProjectConfig, AnalysisResult]
    end

    subgraph adapters[Adapters · I/O externo]
        cg[code_gen/<br/>riverpod_manual · bloc]
        tc[token_catalog/<br/>dart_source · json]
        ana[analyzers/<br/>17 reglas]
    end

    bin --> runner
    runner --> cmd
    cmd --> services
    services --> contracts_layer
    adapters --> contracts_layer

    style contracts_layer fill:#FCEDF6,stroke:#DA1884,stroke-width:2px
    style entry fill:#E0F5F5
```

**Invariantes duros** (enforced en CI por `PackageBoundaryAnalyzer` — ver [adr/0001-architectural-invariants.md](adr/0001-architectural-invariants.md)):

- `contracts/` es puro — solo `dart:core`, `dart:async`, `dart:convert`, `package:meta`.
- `matching/` es puro — sin I/O, sin analyzer, sin path.
- `analyzers/` NO importa `adapters/`.
- `core/` NO importa `adapters/` — selección por nombre vía `ProjectConfig` en runtime.
- `resolvers/`, `inventory/`, `scaffolding/` NO importan `adapters/`.

**Comienza por:** [../README.md#project-layout](../README.md) para el árbol de directorios anotado.

---

## 3. Arquitectura: Ports & Adapters

ALEA aplica tres patrones que convergen en la misma idea:

- **Ports and Adapters** (Cockburn) — el core conoce los puertos (interfaces), nunca los adapters.
- **Anti-Corruption Layer** (Evans) — cada adapter traduce el vocabulario externo a una forma canónica.
- **Gateway** (Fowler) — cada adapter es el único punto de acceso a un sistema externo.

```mermaid
flowchart TB
    config[.alea.yaml<br/>consumer config]

    subgraph core_ring[Core · orquestación]
        direction TB
        cmd[core/commands/<br/>pipeline · analyze-ticket<br/>design-feature · implement-*]
    end

    subgraph contracts_ring[Contracts · API estable]
        direction TB
        c1[DesignSourceAdapter]
        c2[CodeGenAdapter]
        c3[TicketSourceAdapter]
        c4[Analyzer]
        c5[Gate]
    end

    subgraph adapters_ring[Adapters · implementaciones]
        direction LR
        subgraph ds[design_source/]
            figma[figma/]
            image[image/]
            markup[markup/]
        end
        subgraph cg[code_gen/]
            riv[riverpod_manual/]
            bloc[bloc/]
            prov[provider/]
        end
        subgraph ts[ticket_source/]
            asana[asana/]
            file[file/]
        end
    end

    config -.declara nombres.-> core_ring
    core_ring -->|depends on| contracts_ring
    adapters_ring -->|implements| contracts_ring

    style contracts_ring fill:#FCEDF6,stroke:#DA1884,stroke-width:2px
    style config fill:#4A0E2B,color:#fff
```

**La regla que une los tres patrones:**

> Para cada familia de dependencia externa existe **exactamente UNA forma canónica** que fluye al core. Ningún campo, enum value o nombre adapter-específico aparece en la forma canónica.

| Familia | Forma canónica | Definida en |
|---|---|---|
| Ticket sources | `RawTicketPayload` | [../adapters/ticket_source/README.md](../adapters/ticket_source/README.md) |
| Design sources | `NDS` (Normalized Design Spec) | [../contracts/schemas/nds.schema.yaml](../contracts/schemas/nds.schema.yaml) |
| Code-gen targets | `CodeGenResult` | [../contracts/code_gen_adapter.dart](../contracts/code_gen_adapter.dart) |

**Comienza por:** [../ARCHITECTURE.md](../ARCHITECTURE.md) (la tabla "Principles applied" es oro — 11 principios SOLID/DDD aplicados con ejemplo concreto en ALEA).

---

## 4. Secuencia de una corrida completa

Una invocación de `/aflow-pipeline DEV-1234` ejecuta esto (modo `auto` — sin paradas humanas):

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Developer
    participant CC as Claude Code
    participant P as /aflow-pipeline
    participant A as /aflow-analyze-ticket
    participant TS as ticket_source<br/>adapter
    participant DF as /aflow-design-feature
    participant DS as design_source<br/>adapter
    participant IMP as /implement-*
    participant CG as code_gen<br/>adapter
    participant G as /aflow-run-gates
    participant CLI as alea CLI
    participant R as /review · /aflow-create-mr · /aflow-qa-handoff
    participant FS as .pipeline/runs/DEV-1234/

    Dev->>CC: /aflow-pipeline DEV-1234 --mode auto
    CC->>P: invoca
    P->>FS: crea tag git pipeline-DEV-1234-start
    P->>A: invoca

    A->>TS: extrae ticket
    TS-->>A: RawTicketPayload
    A->>A: redacta PII (RFC, CURP, ...)
    A->>FS: escribe analysis.json

    P->>DF: invoca (si feature)
    DF->>DS: extrae diseño
    DS-->>DF: NDS YAML
    DF->>FS: escribe spec.json + nds.yaml

    loop por capa: domain, infra, presentation
        P->>IMP: invoca
        IMP->>CG: genera código
        CG-->>IMP: Dart files + impl markdown
        IMP->>FS: escribe <layer>_impl.md
    end

    P->>G: invoca
    G->>CLI: aflow analyze --gate <name>
    CLI-->>G: AnalysisIssue[] por analyzer
    G->>FS: escribe gate_report.json

    alt gate falla
        P->>P: aborta o pide intervención
    else gate pasa
        P->>R: review → MR → handoff
        R->>FS: escribe review.md, mr.json, qa_handoff.md
    end

    P-->>Dev: imprime summary block (═══)
```

**Notas importantes:**

- `/aflow-pipeline` es **reanudable**: si se interrumpe, vuelve a correrla y detecta qué artefacto existe último para continuar desde ahí. NUNCA borres artefactos a mano. Usa `--reset` para empezar de cero (crea nuevo tag).
- **Modos** (`pipeline.default_mode` en `.alea.yaml`):
  - `guided` — para en cada gate para aprobación humana.
  - `semi` — solo para en Gate 0 (spec) y Gate Final (review).
  - `auto` — solo para en falla de validator.
- **Cost tracking** — cada fase añade a `metrics.json::estimated_cost_usd`. Si rebasa `cost_warn_usd` avisa; si rebasa `cost_hard_stop_usd` aborta.
- **Circuit breaker design-source** — si un adapter acumula hallucinations sobre cierto umbral, `pipeline-feedback` lo deshabilita en `.pipeline/config.json` automáticamente.

**Comienza por:** [../core/commands/aflow-pipeline.md](../core/commands/aflow-pipeline.md) (es el corazón del flujo; léelo entero antes de ejecutar manualmente cualquier fase).

---

## 5. Selección de adapters en runtime

¿Cómo es que `core/` "no conoce" qué adapter usar pero termina llamando al correcto?

```mermaid
flowchart TB
    cmd[core/commands/aflow-analyze-ticket<br/>arranca]
    config[ProjectConfig<br/>cargado de .alea.yaml]
    name{ticket_source.adapter<br/>= ?}
    reg[registry.dart<br/>name → Adapter constructor]

    cmd --> config
    config --> name
    name -->|asana| ra[AsanaTicketAdapter]
    name -->|linear| rl[LinearTicketAdapter]
    name -->|file| rf[FileTicketAdapter]
    name -.no encontrado.-> err[ConfigError<br/>exit 2]

    ra --> reg
    rl --> reg
    rf --> reg

    reg --> impl[adapter.fetch ticketId]
    impl --> payload[RawTicketPayload<br/>canonical shape]
    payload --> back[regresa a core/commands]

    style config fill:#FCEDF6
    style payload fill:#E0F5F5
    style err fill:#DA1884,color:#fff
```

**El truco:** `core/` solo conoce **el nombre del adapter como string**. El registry mapea ese string a un constructor. El adapter implementa la interfaz declarada en `contracts/`. Una vez devuelve `RawTicketPayload`, el resto del core no sabe (ni le importa) de qué sistema vino el dato.

Esta es la única manera en que se cumple **OCP**: agregar Jira = crear `adapters/ticket_source/jira/` + registrar nombre. Cero modificaciones a `core/` o `contracts/`.

**Comienza por:** [../lib/src/core/registry.dart](../lib/src/core/registry.dart) y [../lib/src/contracts/](../lib/src/contracts/) (las interfaces son cortas — léelas todas).

---

## 6. Flujo de artefactos

Cada comando es una **función pura desde el punto de vista de artefactos**: lee N archivos, escribe M archivos, persiste todo en `.pipeline/runs/<ticket_id>/`.

```mermaid
graph LR
    yaml[.alea.yaml]
    ticket[ticket source<br/>Asana / file / ...]
    design[design source<br/>Figma / image / ...]

    yaml --> AT[/aflow-analyze-ticket/]
    ticket --> AT
    AT --> analysisJson[analysis.json]

    analysisJson --> DF[/aflow-design-feature/]
    design --> DF
    DF --> specJson[spec.json]
    DF --> ndsYaml[nds.yaml]

    specJson --> ImpD[/aflow-implement-domain/]
    ImpD --> domainImpl[domain_impl.md<br/>+ Dart files]

    specJson --> ImpI[/aflow-implement-infrastructure/]
    ndsYaml --> ImpI
    ImpI --> infraImpl[infrastructure_impl.md<br/>+ Dart files]

    specJson --> ImpP[/aflow-implement-presentation/]
    ndsYaml --> ImpP
    ImpP --> presImpl[presentation_impl.md<br/>+ Dart files]

    domainImpl --> RG[/aflow-run-gates/]
    infraImpl --> RG
    presImpl --> RG
    yaml --> RG
    RG --> gateReport[gate_report.json]

    gateReport --> RV[/aflow-review-feature/]
    specJson --> RV
    RV --> reviewMd[review.md]

    reviewMd --> CMR[/aflow-create-mr/]
    CMR --> mrJson[mr.json]

    mrJson --> QH[/aflow-qa-handoff/]
    QH --> qaMd[qa_handoff.md]

    classDef artifact fill:#E0F5F5,stroke:#4A0E2B
    classDef external fill:#FCEDF6,stroke:#DA1884
    class analysisJson,specJson,ndsYaml,domainImpl,infraImpl,presImpl,gateReport,reviewMd,mrJson,qaMd artifact
    class yaml,ticket,design external
```

**Reglas:**

1. **Nunca renombres un artefacto.** El nombre del archivo es contrato — `/aflow-pipeline`'s resume detecta avance por presencia de archivos con nombres específicos.
2. **Cada comando imprime un summary block delimitado por `═══`** — es la forma estandarizada de comunicar al usuario qué se escribió.
3. **Los schemas** que validan estos artefactos viven en [../contracts/schemas/](../contracts/schemas/).

**Comienza por:** [../ARCHITECTURE.md#module-responsibilities](../ARCHITECTURE.md) (tabla con Reads/Writes/Knows-about por módulo).

---

## 7. Mapa del CLI

El CLI Dart (compilable a binario nativo de ~10MB) expone 14 subcomandos. La capa de orquestación (slash commands) los invoca; tú también puedes hacerlo directo en CI o en exploración manual.

```mermaid
flowchart TB
    cli["alea (binary)"]

    cli --> init["aflow init [name]<br/>--template project|feature"]
    cli --> analyze["aflow analyze<br/>--gate domain|infra|presentation"]
    cli --> match["aflow match<br/>color #HEX | typography | layout"]
    cli --> scaffold["aflow scaffold &lt;name&gt;<br/>--layer X --style Y"]
    cli --> inventory["aflow inventory<br/>--output JSON"]
    cli --> journal["aflow journal<br/>--run-directory PATH"]
    cli --> context["aflow context<br/>--run-directory PATH"]

    init --> bootstrap[Project / feature skeleton<br/>.alea.yaml + layer dirs<br/>+ theme stub]

    analyze -.lee.-> conf[.alea.yaml]
    analyze --> gateJson[gate_report.json]

    match -.lee.-> tokenCatalog[token catalog<br/>via adapter]
    match --> stdout1[stdout: match result]

    scaffold -.lee.-> conf
    scaffold --> dartFiles[Dart files en consumer]

    inventory --> jsonOut[widget_inventory.json]

    journal -.lee.-> jsonl[run journal JSONL]
    journal --> stdout2[stdout: tabla legible]

    context -.lee.-> runDir[.pipeline/runs/.../]
    context --> packet[context_packet.json<br/>cacheable, TTL]

    style cli fill:#DA1884,color:#fff
    style init fill:#E0F5F5
```

| Subcomando | Para qué sirve | Exit codes |
|---|---|---|
| `init` | Bootstrap de skeleton ALEA — template `project` (Flutter app post-`flutter create`) o `feature` (Dart package en monorepo). Idempotente; respeta `--force` y `--dry-run`. Ver [ADR-0011](adr/0011-monorepo-and-bootstrap-strategy.md). | `0` aplicado · `64` invalid name |
| `analyze` | Corre todos los analyzers de un gate específico contra archivos cambiados (o todo el árbol) | `0` pass · `1` blocker/critical · `2` config error |
| `match` | Resuelve un valor (color hex, font size, spacing) contra el token catalog del consumer | `0` match exacto · `1` near-miss · `2` no encontrado |
| `scaffold` | Crea archivos boilerplate de un feature en una capa (idempotente, con rollback) | `0` aplicado · `1` conflict (necesita `--force`) |
| `inventory` | Escanea widgets del consumer y emite JSON con conteo, props, ubicación | `0` siempre (a menos que I/O falle) |
| `journal` | Lee el JSONL de eventos de una corrida y lo imprime legible | `0` siempre |
| `context` | Construye un "context packet" cacheable (con TTL y hash) para alimentar al siguiente LLM call | `0` packet generado · `1` falta input |

**Comienza por:** [../bin/aflow.dart](../bin/aflow.dart) (22 LOC, es el shim) → [../lib/src/cli/cli_runner.dart](../lib/src/cli/cli_runner.dart) → cada `commands/*_command.dart` por separado.

---

## 8. Onboarding de un consumer

```mermaid
flowchart TB
    start[Tienes un proyecto Flutter<br/>y quieres adoptar ALEA]
    s1[1 — Instalar ALEA<br/>dart pub global activate --source path]
    s2[2 — Crear .alea.yaml<br/>en la raíz del proyecto]
    s3[3 — Configurar layers<br/>domain / infra / presentation]
    s4[4 — Elegir adapters<br/>ticket_source · design_source · code_gen]
    s5[5 — Definir thresholds<br/>coverage por capa]
    s6[6 — Smoke test<br/>aflow analyze --gate domain]
    s7{¿pasa?}
    s8[7 — Probar /aflow-pipeline<br/>con un ticket pequeño]
    s9[Iterar config hasta<br/>tener parity con tu flujo]
    fix[Ajustar paths / forbid_imports]

    start --> s1 --> s2 --> s3 --> s4 --> s5 --> s6 --> s7
    s7 -->|sí| s8 --> s9
    s7 -->|no| fix --> s6

    style start fill:#E0F5F5
    style s9 fill:#FCEDF6
```

**Toda la guía detallada paso-a-paso está en [CONSUMER_INTEGRATION.md](CONSUMER_INTEGRATION.md) (614 líneas).** Léela completa antes de añadir tu primer `.alea.yaml`.

---

## 9. Decisiones clave (ADRs)

Los ADRs son cortos (~3KB cada uno) y explican el "por qué" de cada decisión arquitectónica. Léelos en orden — están numerados por la secuencia en que se tomaron durante el rediseño.

```mermaid
flowchart LR
    a1[0001<br/>Architectural<br/>invariants] --> a2[0002<br/>Run journal]
    a2 --> a3[0003<br/>Design token<br/>catalog]
    a3 --> a4[0004<br/>Token resolvers<br/>+ matching lib]
    a4 --> a5[0005<br/>Visual fidelity<br/>with catalog]
    a5 --> a6[0006<br/>Widget inventory<br/>+ SymbolDigest]
    a6 --> a7[0007<br/>Wiring<br/>cohesion]
    a7 --> a8[0008<br/>Executable<br/>code-gen]
    a8 --> a9[0009<br/>Context<br/>packet]
    a9 --> a10[0010<br/>CLI<br/>consolidation]

    style a1 fill:#FCEDF6
    style a10 fill:#E0F5F5
```

| # | ADR | Por qué importa |
|---|---|---|
| 0001 | [Architectural invariants](adr/0001-architectural-invariants.md) | Define las 5 reglas duras de imports que `PackageBoundaryAnalyzer` enforcea en CI. Es la base. |
| 0002 | [Run journal](adr/0002-run-journal.md) | Formato JSONL con redaction de PII para observabilidad. Necesario antes de cualquier costing o circuit-breaker. |
| 0003 | [Design token catalog](adr/0003-design-token-catalog.md) | Cómo se extraen tokens del consumer (adapter `dart_source` o `json`). Habilita matching. |
| 0004 | [Token resolvers + matching](adr/0004-token-resolvers-and-matching-library.md) | Biblioteca **pura** de matching (ΔE CIE2000, Jaccard). El cerebro del visual fidelity. |
| 0005 | [Visual fidelity with catalog](adr/0005-visual-fidelity-with-catalog.md) | Cómo el analyzer usa el catalog para detectar `color_not_in_catalog`, etc. |
| 0006 | [Widget inventory + SymbolDigest](adr/0006-widget-inventory-and-symbol-digest.md) | Reducción de tokens ≥70% para LLM context. Habilita corridas baratas. |
| 0007 | [Wiring cohesion](adr/0007-wiring-cohesion.md) | Analyzer config-driven de registro DI/route. |
| 0008 | [Executable code-gen](adr/0008-executable-code-generation.md) | Adapters Riverpod-manual y Bloc; idempotencia + rollback. |
| 0009 | [Context packet](adr/0009-context-packet.md) | Caching con TTL + hash invalidation. |
| 0010 | [CLI consolidation](adr/0010-cli-consolidation.md) | Unificación a `alea (analyze | match | scaffold | inventory | journal | context)`. |

**Comienza por:** [adr/0001-architectural-invariants.md](adr/0001-architectural-invariants.md) — sin entender los invariantes, el resto se siente arbitrario.

---

## 10. Ruta de lectura recomendada — orden definitivo

Si tienes **1 hora**: 1 → 2 → 3 (no leas más, ejecuta el quickstart).

Si tienes **medio día**: 1–7.

Si vas a contribuir código: lee todo, incluyendo cada README por subdirectorio.

| # | Archivo | Lo que aprendes | Tiempo |
|---|---|---|---|
| 1 | [../README.md](../README.md) | Qué es ALEA, status, quickstart, layout | 10 min |
| 2 | Este archivo (§1–§7) | Vista visual + flujo de una corrida | 15 min |
| 3 | [../ARCHITECTURE.md](../ARCHITECTURE.md) | Patrones aplicados, contratos, extension points | 20 min |
| 4 | [CONSUMER_INTEGRATION.md](CONSUMER_INTEGRATION.md) | Cómo adoptar ALEA en un proyecto real | 30 min |
| 5 | [adr/0001-architectural-invariants.md](adr/0001-architectural-invariants.md) | Las reglas duras que CI enforcea | 10 min |
| 6 | [../core/commands/aflow-pipeline.md](../core/commands/aflow-pipeline.md) | El orquestador maestro | 20 min |
| 7 | [../lib/src/contracts/](../lib/src/contracts/) (todos los `.dart`) | La superficie API estable | 15 min |
| 8 | [adr/0002](adr/0002-run-journal.md) → [adr/0011](adr/0011-monorepo-and-bootstrap-strategy.md) | Las 10 decisiones siguientes en orden | 1.5 h |
| 9 | [../adapters/README.md](../adapters/README.md) + un adapter completo (ej. [../adapters/code_gen/riverpod_manual/README.md](../adapters/code_gen/riverpod_manual/README.md)) | Cómo se ve un adapter concreto | 30 min |
| 10 | [../lib/src/analyzers/](../lib/src/analyzers/) (browse) | Cómo se implementa un analyzer | 30 min |

---

## 11. Glosario rápido

| Término | Qué es |
|---|---|
| **Consumer** | Proyecto Flutter que adopta ALEA poniendo un `.alea.yaml` en su raíz. |
| **`.alea.yaml`** | Único archivo de config del consumer; declara package name, layers, adapters elegidos, thresholds, brand tokens. |
| **Adapter** | Folder bajo `adapters/<family>/<name>/` que implementa una interfaz de `contracts/` para un sistema externo concreto. |
| **NDS** | Normalized Design Spec — forma canónica que produce cualquier design-source adapter. |
| **Gate** | Validación de salida/calidad de una fase. Puede fallar la corrida. |
| **Analyzer** | Regla automatizada que escanea código fuente y emite `AnalysisIssue[]`. |
| **Slash command** | Markdown en `core/commands/` que un IDE (Claude Code, Cursor, Gemini CLI) interpreta como prompt orquestado. |
| **Run journal** | `events.jsonl` por corrida — la fuente de verdad para observabilidad y costo. |
| **Context packet** | Cacheable bundle de contexto LLM con TTL y hash de invalidación. |
| **Circuit breaker** | Mecanismo que deshabilita un adapter automáticamente si su tasa de hallucinations excede el umbral. |

---

*Última actualización: 2026-05-24. Si actualizas la arquitectura o agregas un adapter / analyzer, actualiza también el diagrama correspondiente.*
