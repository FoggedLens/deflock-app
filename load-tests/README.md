# Deflock Load Tests

Gatling load tests for validating [`overpass.deflock.org`](https://overpass.deflock.org) performance before rolling it out as the primary Overpass API endpoint for all Deflock app users.

## What is this?

The Deflock app fetches surveillance camera data from the [Overpass API](https://wiki.openstreetmap.org/wiki/Overpass_API) every time a user pans or zooms the map. We've deployed our own Overpass instance at `overpass.deflock.org` to reduce dependence on the public endpoint. These load tests validate that our instance can handle realistic traffic patterns before we switch users over to it.

The tests use [Gatling](https://gatling.io), an open-source load testing framework. Gatling simulates virtual users sending HTTP requests and produces detailed HTML reports with latency percentiles, error rates, and throughput metrics.

## Quick start

### Prerequisites

- **JDK 21+** — install via [SDKMAN](https://sdkman.io) (`sdk install java 21-tem`) or your package manager
- **No other tools needed** — Gradle and Scala are handled automatically by the included wrapper and build config

Or use the included [dev container](#dev-container) to skip local setup entirely.

### Run the tests

```bash
cd load-tests
./gradlew gatlingRun                                                   # baseline (default)
./gradlew gatlingRun --simulation deflock.ConcurrentSimulation         # concurrent users
./gradlew gatlingRun --simulation deflock.StressSimulation             # stress test
./gradlew gatlingRun --simulation deflock.BurstSimulation              # burst traffic
```

When finished, Gatling prints a `file://` URL to the HTML report — open it in your browser. Reports land in `build/reports/gatling/<simulation-name-timestamp>/index.html`.

### Run via GitHub Actions

1. Go to the **Actions** tab in GitHub
2. Select the **"Load Test"** workflow
3. Click **"Run workflow"** and pick a scenario from the dropdown:
   - **baseline** — single-user zoom progression (~2 minutes)
   - **concurrent** — ramp to 50 users over 4 minutes
   - **stress** — spike to 500 users over 5 minutes
   - **burst** — realistic wave pattern over ~3 minutes
   - **all** — run all 4 in parallel on separate runners
4. When complete, download the **gatling-report-{name}** artifact (retained for 30 days)

## Scenarios

### Baseline (`OverpassSimulation`)

A single virtual user walks through zoom levels z15→z10, querying every city at each level (6 zooms × 6 cities = 36 deterministic requests). Measures how response time scales with viewport size.

- **Duration:** ~2 minutes
- **Assertions:** p99 < 30s, errors < 5%

### Concurrent (`ConcurrentSimulation`)

Ramps from 1 to 50 users over 2 minutes. Each user loops forever with random city/zoom picks and 500ms pauses until the 4-minute max duration. Designed to find the degradation inflection point — where does p95 start climbing?

- **Duration:** 4 minutes (max)
- **Assertions:** p95 < 45s, errors < 20%
- **Look for:** inflection point in "Response time percentiles over time" chart

### Stress (`StressSimulation`)

Three phases totaling 500 users: warmup ramp (100 over 30s), spike (200 at once), sustained ramp (200 over 30s). Uses 100ms pauses and shared connections. Designed to exceed the server's ~512 Overpass compute slots.

- **Duration:** 5 minutes (max)
- **Assertions:** none meaningful (just `requestsPerSec > 0`)
- **Expected failures:** 429s (slot exhaustion), 502/503s (nginx), timeouts
- **Look for:** when errors start, throughput plateau/collapse, bimodal latency

### Burst (`BurstSimulation`)

Models real app usage: each user does 10-20 requests (a map browsing session) then exits. Users arrive in waves (20→50→100→80) with gaps between waves. Uses weighted zoom feeder (80% z13-z15) matching real user behavior.

- **Duration:** ~3 minutes
- **Assertions:** p95 < 30s, errors < 10%
- **Look for:** wave pattern in active users chart, recovery between bursts

### Test data

Six US cities were chosen for high surveillance camera density in their downtown areas:

| City | Center coordinates | Landmark |
|---|---|---|
| Denver | 39.75, -105.00 | 16th St Mall / Union Station |
| Los Angeles | 34.05, -118.25 | Pershing Square, DTLA |
| San Francisco | 37.79, -122.40 | Financial District |
| New York | 40.75, -73.98 | Midtown / 42nd & 6th Ave |
| Boston | 42.36, -71.06 | Downtown Crossing |
| Chicago | 41.88, -87.63 | State & Madison, The Loop |

### Zoom levels and viewport sizes

Each zoom level corresponds to a different viewport size on a typical mobile phone screen (~400x800px, portrait):

| Zoom | Area covered | Lat x Lng span |
|---|---|---|
| 15 | A few city blocks (~1.5 x 3 km) | 0.026 x 0.017 deg |
| 14 | A neighborhood (~3 x 6 km) | 0.053 x 0.034 deg |
| 13 | A district (~6 x 12 km) | 0.105 x 0.069 deg |
| 12 | A mid-size city (~12 x 23 km) | 0.210 x 0.140 deg |
| 11 | A large city (~23 x 47 km) | 0.420 x 0.270 deg |
| 10 | A metro region (~47 x 93 km) | 0.840 x 0.550 deg |

## Interpreting the report

The Gatling HTML report includes several views. Here's what to look for:

### Key metrics

- **p50 (median) latency** — what a typical user experiences
- **p95 latency** — should be under 10s for a good user experience
- **p99 latency** — should be under 30s (the assertion threshold)
- **Error rate** — should be 0% under single-user load

### Report sections

- **Response time distribution** — histogram showing how many requests fell into each latency bucket
- **Response time percentiles over time** — trend lines for p50/p75/p95/p99 throughout the test
- **Requests per second** — throughput over the test duration
- **Individual request details** — click any request name (e.g., "Overpass z15 - Denver") to see its specific metrics

### What "good" looks like

From our baseline runs, typical single-user performance is:

| Zoom | Expected latency |
|---|---|
| z15 (blocks) | ~400-600ms |
| z13-z14 (neighborhood) | ~600-1000ms |
| z10-z11 (city/metro) | ~1000-1600ms |

## Project structure

```
load-tests/
├── .devcontainer/             # VS Code dev container (JDK 21 + Scala)
│   ├── devcontainer.json
│   └── Dockerfile
├── build.gradle.kts           # Build config (Gatling + Scala + test plugins)
├── settings.gradle.kts        # Gradle project name
├── gradlew / gradlew.bat      # Gradle wrapper (no global install needed)
├── gradle/wrapper/            # Gradle wrapper jar + config
├── src/
│   ├── shared/scala/deflock/  # Pure logic (no Gatling dependency)
│   │   ├── TestData.scala     #   City data, viewports, feeders, buildFeedEntry
│   │   └── OverpassQuery.scala#   Query builder, timeouts, tag filters, constants
│   ├── gatling/
│   │   ├── scala/deflock/     # Gatling simulations (depend on shared)
│   │   │   ├── OverpassSimulation.scala    # Baseline: single-user zoom progression
│   │   │   ├── ConcurrentSimulation.scala  # Ramp to 50 users
│   │   │   ├── StressSimulation.scala      # Spike to 500 users
│   │   │   ├── BurstSimulation.scala       # Realistic wave pattern
│   │   │   └── OverpassRequests.scala      # Gatling HTTP request def + feederForZoom
│   │   └── resources/
│   │       ├── gatling.conf   # Gatling charting config
│   │       └── logback-test.xml
│   └── test/scala/deflock/    # Unit tests for shared logic (ScalaTest)
│       ├── TestDataSpec.scala
│       └── OverpassQuerySpec.scala
└── build/reports/gatling/     # Generated HTML reports (.gitignored)
```

The `shared` source set contains pure Scala logic with no Gatling dependency. Both the `gatling` source set (simulations) and the `test` source set (unit tests) depend on it. This avoids a circular dependency that would occur if tests depended directly on the Gatling source set.

Run unit tests with `./gradlew test`.

## Dev container

If you don't want to install JDK locally, the included dev container provides a ready-to-go environment:

1. Open the `load-tests/` folder in VS Code
2. Install the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
3. Press `Ctrl+Shift+P` → "Dev Containers: Reopen in Container"
4. Wait for the container to build (first time takes a few minutes)
5. Open a terminal and run `./gradlew gatlingRun`

The container includes JDK 21, Scala (via [Coursier](https://get-coursier.io)), and VS Code extensions for Scala (Metals) and Gradle.
