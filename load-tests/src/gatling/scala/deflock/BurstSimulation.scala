package deflock

import io.gatling.core.Predef._
import io.gatling.http.Predef._

import scala.concurrent.duration._
import java.util.concurrent.ThreadLocalRandom

/**
 * Realistic burst simulation modeling actual Deflock app usage patterns.
 *
 * Each virtual user represents one app session: the user opens the app,
 * pans/zooms the map 10-20 times (each interaction triggers an Overpass
 * query), then closes the app. Pauses between requests are 200-800ms,
 * matching the time it takes to pan/zoom on a phone.
 *
 * Users arrive in waves, simulating the bursty nature of real traffic
 * (e.g., morning commutes, lunch breaks):
 *   Wave 1:  20 users over 15s  (light morning traffic)
 *   Gap:     10s
 *   Wave 2:  50 users over 15s  (mid-morning pickup)
 *   Gap:     10s
 *   Wave 3: 100 users over 20s  (lunch rush)
 *   Gap:     10s
 *   Wave 4:  80 users over 30s  (sustained afternoon)
 *
 * Uses the weighted zoom feeder (z13-z15 heavy) since most real users
 * are zoomed in to neighborhood level.
 *
 * == What to look for in the report ==
 *
 * - Response time should stay relatively stable during waves 1-2, then
 *   may degrade during wave 3 (the peak).
 * - The "Active users over time" chart should show the wave pattern.
 * - Compare error rates between waves to see if the server recovers
 *   between bursts.
 *
 * == Running ==
 * {{{
 * cd load-tests
 * ./gradlew gatlingRun --simulation deflock.BurstSimulation
 * }}}
 */
class BurstSimulation extends Simulation {

  val httpProtocol = http
    .baseUrl("https://overpass.deflock.org")
    .userAgentHeader("DeFlock/LoadTest-Burst (+https://deflock.org)")
    .acceptHeader("application/json")

  // Each user does 10-20 requests (a realistic app session), then exits.
  val burstScenario = scenario("Burst app sessions")
    .repeat(session => 10 + ThreadLocalRandom.current().nextInt(11)) {
      feed(TestData.weightedZoomFeeder)
        .exec(OverpassRequests.overpassRequest)
        .pause(200.milliseconds, 800.milliseconds)
    }

  setUp(
    burstScenario.inject(
      rampUsers(20).during(15.seconds),    // Wave 1: light traffic
      nothingFor(10.seconds),
      rampUsers(50).during(15.seconds),    // Wave 2: mid-morning
      nothingFor(10.seconds),
      rampUsers(100).during(20.seconds),   // Wave 3: lunch rush
      nothingFor(10.seconds),
      rampUsers(80).during(30.seconds)     // Wave 4: sustained afternoon
    )
  ).protocols(httpProtocol)
    .maxDuration(10.minutes)
    .assertions(
      global.responseTime.percentile(95).lt(30000),
      global.failedRequests.percent.lt(10.0)
    )
}
