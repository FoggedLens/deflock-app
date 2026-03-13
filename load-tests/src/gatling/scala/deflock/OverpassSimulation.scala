package deflock

import io.gatling.core.Predef._
import io.gatling.http.Predef._

import scala.concurrent.duration._

/**
 * Gatling simulation for load-testing the Deflock Overpass API endpoint.
 *
 * This simulation validates the performance of overpass.deflock.org before
 * it becomes the primary endpoint for all Deflock app users. It sends
 * Overpass queries using the same per-profile tag filters as the app
 * (see OverpassQuery.tagFilters and lib/models/node_profile.dart).
 *
 * == How it works ==
 *
 * A single virtual user walks through zoom levels from tightest (z15, a few
 * city blocks) to widest (z10, a metro region). At each zoom level, it
 * queries every city deterministically — no randomization — so results are
 * reproducible and city-to-city variance is visible in the report.
 *
 * This progression reveals how response time scales with viewport size —
 * larger viewports return more surveillance nodes, producing bigger responses.
 *
 * == Running ==
 *
 * {{{
 * cd load-tests
 * ./gradlew gatlingRun
 * }}}
 *
 * The HTML report will be in build/reports/gatling/ — open index.html.
 *
 */
class OverpassSimulation extends Simulation {

  // Target our self-hosted Overpass instance (not the public OSMF one).
  // The User-Agent identifies load test traffic in server logs.
  val httpProtocol = http
    .baseUrl("https://overpass.deflock.org")
    .userAgentHeader("DeFlock/LoadTest (+https://deflock.org)")
    .acceptHeader("application/json")

  // Walk through zoom levels from tightest (z15) to widest (z10).
  // At each zoom level, query every city deterministically so results
  // are reproducible and per-city variance is visible in the report.
  //
  // The nested flatMap produces a chain of (zoom × city) steps. For
  // 6 zoom levels × 6 cities = 36 total requests with 500ms pauses.
  val baselineScenario = scenario("Single-user zoom progression")
    .exec(
      TestData.zoomViewports.flatMap { viewport =>
        TestData.cities.map { city =>
          exec(_.setAll(TestData.buildFeedEntry(city, viewport)))
            .exec(OverpassRequests.overpassRequest)
            .pause(500.milliseconds)
        }
      }.reduce(_.exec(_))
    )

  // --- Test setup ---
  // atOnceUsers(1): inject exactly 1 virtual user immediately (no ramp-up).
  // This is a baseline test — we want clean, isolated measurements before
  // adding concurrency in future scenarios.
  setUp(
    baselineScenario.inject(atOnceUsers(1))
  ).protocols(httpProtocol)
    .assertions(
      // p99 response time under 30 seconds (generous for Overpass)
      global.responseTime.percentile(99).lt(30000),
      // Less than 5% of requests should fail
      global.failedRequests.percent.lt(5.0)
    )
}
