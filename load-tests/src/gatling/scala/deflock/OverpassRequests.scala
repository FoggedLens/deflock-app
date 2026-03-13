package deflock

import io.gatling.core.Predef._
import io.gatling.http.Predef._

/**
 * Gatling-specific Overpass API request definitions and feeders.
 *
 * Pure logic (query building, constants, timeouts) lives in OverpassQuery
 * (shared source set). This object adds the Gatling HTTP DSL wrappers and
 * the feederForZoom method that uses Gatling's .random extension.
 *
 * The request format mirrors the Deflock app (POST to /api/interpreter
 * with form-encoded Overpass QL) using the same per-profile tag filters.
 * See OverpassQuery.tagFilters for details.
 */
object OverpassRequests {

  /**
   * Create a Gatling feeder that picks a random city for a given zoom level.
   *
   * A "feeder" in Gatling is a data source that injects variables into the
   * virtual user's session before each request. This one pre-computes the
   * Overpass query body so it's built once at startup, not on every request.
   *
   * @param viewport The zoom level and its corresponding viewport dimensions
   * @return A Gatling feeder that randomly selects a city and provides session
   *         variables: cityName, zoomLevel, and the pre-built queryBody
   */
  def feederForZoom(viewport: ZoomViewport) =
    TestData.cities.map(TestData.buildFeedEntry(_, viewport)).toIndexedSeq.random

  /**
   * The HTTP request definition that Gatling will execute.
   *
   * Uses Gatling's #{...} Expression Language syntax to inject session
   * variables at request time. These variables are populated by the feeders
   * in TestData — see feederForZoom() and the infinite feeders.
   *
   * The request name (e.g., "Overpass z15 - Denver") appears in the Gatling
   * HTML report, making it easy to compare performance across zoom levels
   * and cities.
   *
   * Checks:
   * - HTTP 200 status (Overpass returns 200 even for empty results)
   * - Response body contains an "elements" array (valid Overpass JSON)
   */
  val overpassRequest = http("Overpass z#{zoomLevel} - #{cityName}")
    .post("/api/interpreter")
    .formParam("data", "#{queryBody}")
    .requestTimeout(OverpassQuery.clientTimeout)
    .check(status.is(200))
    .check(jsonPath("$.elements").exists)
}
