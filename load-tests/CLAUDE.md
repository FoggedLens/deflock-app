# Load Tests

Gatling load tests for `overpass.deflock.org`. Scala 2.13, Gradle build, JDK 21.

## Architecture

Three source sets to avoid circular dependencies:

- **`src/shared/`** — Pure Scala logic (no Gatling dependency). `OverpassQuery` (query builder, tag filters, timeouts) and `TestData` (cities, viewports, feeders).
- **`src/gatling/`** — Gatling simulations. Depends on `shared`. Contains `OverpassRequests` (HTTP request def) and four simulations.
- **`src/test/`** — ScalaTest unit tests. Depends on `shared`. Tests pure logic without Gatling.

The `shared` source set exists because the Gatling Gradle plugin creates a circular dependency if `test` depends on `gatling` output directly.

## Key files

| File | Purpose |
|---|---|
| `src/shared/scala/deflock/OverpassQuery.scala` | Query builder, tag filters (must match app), timeouts |
| `src/shared/scala/deflock/TestData.scala` | Cities, viewports, feeders (`randomFeeder`, `weightedZoomFeeder`) |
| `src/gatling/scala/deflock/OverpassRequests.scala` | Gatling HTTP request definition, `feederForZoom` |
| `src/gatling/scala/deflock/OverpassSimulation.scala` | Baseline: 1 user, all cities x all zooms, deterministic |
| `src/gatling/scala/deflock/ConcurrentSimulation.scala` | Ramp to 50 users, find degradation point |
| `src/gatling/scala/deflock/StressSimulation.scala` | Spike to 500 users, exceed server capacity |
| `src/gatling/scala/deflock/BurstSimulation.scala` | Realistic app sessions in waves |
| `build.gradle.kts` | Gradle config with `shared` source set, ScalaTest deps |

## Commands

```bash
./gradlew gatlingRun                                             # baseline
./gradlew gatlingRun --simulation deflock.ConcurrentSimulation   # concurrent
./gradlew gatlingRun --simulation deflock.StressSimulation        # stress
./gradlew gatlingRun --simulation deflock.BurstSimulation         # burst
./gradlew test                                                   # unit tests
./gradlew compileGatlingScala                                    # compile check
```

Do NOT use `gatlingRun-deflock.ClassName` syntax — it doesn't work with the Gatling Gradle plugin v3.15.0. Use `--simulation` flag instead.

## Tag filter parity

`OverpassQuery.tagFilters` must exactly match the app's `NodeProfile.getDefaults()` in `lib/models/node_profile.dart`. There are 11 built-in profiles. Empty tag values (e.g., `camera:mount: ''`) are filtered out, matching what `OverpassService._buildQuery()` does in `lib/services/overpass_service.dart`.

When profiles change in the app, update `tagFilters` to match.

## Conventions

- Baseline simulation must be deterministic (no randomization) for reproducible results.
- Concurrent/stress/burst simulations use randomized feeders for realistic traffic.
- `ThreadLocalRandom` (not `scala.util.Random`) for feeders used by concurrent simulations.
- Gatling session keys are constants in `OverpassQuery` (`CityName`, `ZoomLevel`, `QueryBody`).
- User-Agent headers identify load test traffic: `DeFlock/LoadTest-{Scenario}`.
- Client timeout = server timeout + 5s so we receive server-side timeout responses.

## GitHub Actions

The `Load Test` workflow (`.github/workflows/load-test.yml`) has a scenario picker dropdown. Reports are uploaded as artifacts. A summary job posts a comment on the PR with download links.

Trigger via Actions tab or API:
```bash
gh api repos/{owner}/{repo}/actions/workflows/{id}/dispatches \
  -f ref=feat/load-tests -f 'inputs[scenario]=baseline'
```
