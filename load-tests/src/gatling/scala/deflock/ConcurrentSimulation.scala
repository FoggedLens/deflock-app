package deflock

import io.gatling.core.Predef._
import io.gatling.http.Predef._

import scala.concurrent.duration._

/**
 * Concurrent user simulation to find the degradation point.
 *
 * Ramps from 1 to 50 virtual users over 2 minutes. Each user loops
 * forever (pick a random city/zoom, send the query, pause 500ms, repeat)
 * until maxDuration (4 minutes total) is reached.
 *
 * The server has ~512 Overpass compute slots behind nginx. This simulation
 * should reveal where latency starts climbing (slot contention) without
 * pushing into outright failure territory.
 *
 * == What to look for in the report ==
 *
 * - The "Response time percentiles over time" chart should show a clear
 *   inflection point where p95 starts climbing — that's the concurrency
 *   level where the server begins queuing requests.
 * - The "Active users over time" chart maps directly to user count.
 * - Compare p50 at 10 users vs 40 users to see degradation magnitude.
 *
 * == Running ==
 * {{{
 * cd load-tests
 * ./gradlew gatlingRun --simulation deflock.ConcurrentSimulation
 * }}}
 */
class ConcurrentSimulation extends Simulation {

  val httpProtocol = http
    .baseUrl("https://overpass.deflock.org")
    .userAgentHeader("DeFlock/LoadTest-Concurrent (+https://deflock.org)")
    .acceptHeader("application/json")

  val concurrentScenario = scenario("Concurrent users")
    .forever {
      feed(TestData.randomFeeder)
        .exec(OverpassRequests.overpassRequest)
        .pause(500.milliseconds)
    }

  setUp(
    concurrentScenario.inject(rampUsers(50).during(2.minutes))
  ).protocols(httpProtocol)
    .maxDuration(4.minutes)
    .assertions(
      // Lenient thresholds — we're exploring capacity, not enforcing SLA
      global.responseTime.percentile(95).lt(45000),
      global.failedRequests.percent.lt(20.0)
    )
}
