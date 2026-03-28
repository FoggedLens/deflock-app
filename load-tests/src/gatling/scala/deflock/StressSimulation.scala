package deflock

import io.gatling.core.Predef._
import io.gatling.http.Predef._

import scala.concurrent.duration._

/**
 * Stress simulation designed to exceed the server's 512 Overpass compute slots.
 *
 * Three phases totaling 500 virtual users:
 *   1. Warmup: ramp to 100 users over 30s
 *   2. Spike: inject 200 users at once
 *   3. Sustained: ramp another 200 users over 30s
 *
 * Each user fires requests with only 100ms pauses — deliberately aggressive
 * to saturate nginx connections and exhaust Overpass slots.
 *
 * `shareConnections` is enabled so that virtual users share the HTTP
 * connection pool. Without this, 500 users would try to open 500 separate
 * TCP connections to the server, and the test would fail on the client side
 * (socket exhaustion) before stressing the server.
 *
 * == Expected failure modes (in order) ==
 *
 * 1. Overpass slot exhaustion → 429 or "rate_limited" responses
 * 2. nginx max connections → 502/503 gateway errors
 * 3. Disk I/O saturation → timeouts on wide-zoom queries
 *
 * == What to look for in the report ==
 *
 * - Error rate timeline: when do errors start, and what type?
 * - Response time distribution: is there a bimodal pattern (fast cache hits
 *   vs slow/failed queries)?
 * - Requests/sec: does throughput plateau or collapse?
 *
 * == Running ==
 * {{{
 * cd load-tests
 * ./gradlew gatlingRun --simulation deflock.StressSimulation
 * }}}
 */
class StressSimulation extends Simulation {

  val httpProtocol = http
    .baseUrl("https://overpass.deflock.org")
    .userAgentHeader("DeFlock/LoadTest-Stress (+https://deflock.org)")
    .acceptHeader("application/json")
    .shareConnections

  val stressScenario = scenario("Stress test")
    .forever {
      feed(TestData.randomFeeder)
        .exec(OverpassRequests.overpassRequest)
        .pause(100.milliseconds)
    }

  setUp(
    stressScenario.inject(
      rampUsers(100).during(30.seconds),   // Phase 1: warmup
      nothingFor(1.second),                // Brief gap so phases are visible in report
      atOnceUsers(200),                    // Phase 2: spike
      rampUsers(200).during(30.seconds)    // Phase 3: sustained pressure
    )
  ).protocols(httpProtocol)
    .maxDuration(5.minutes)
    .assertions(
      // No meaningful SLA — this test is designed to break things.
      // Just verify the test itself ran and produced data.
      global.requestsPerSec.gt(0.0)
    )
}
