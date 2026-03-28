package deflock

import java.util.concurrent.ThreadLocalRandom

/**
 * Center coordinates for a city's downtown area.
 *
 * These are the starting points for building map viewport bounding boxes.
 * Each coordinate was verified against map data and chosen for its high
 * density of surveillance infrastructure (cameras, ALPR, etc.), which
 * produces realistic Overpass API response sizes.
 *
 * @param name  Human-readable city name (appears in Gatling report labels)
 * @param lat   Latitude of the downtown center point
 * @param lng   Longitude of the downtown center point
 */
case class CityCenter(name: String, lat: Double, lng: Double)

/**
 * The dimensions of a map viewport at a given zoom level.
 *
 * These represent what a user sees on their phone screen at each zoom level.
 * Larger viewports (lower zoom) fetch more data from the Overpass API, so
 * we use these to measure how response time scales with area.
 *
 * @param zoom     OSM/Slippy map zoom level (10 = metro region, 15 = a few blocks)
 * @param latSpan  Height of the viewport in degrees of latitude
 * @param lngSpan  Width of the viewport in degrees of longitude
 */
case class ZoomViewport(zoom: Int, latSpan: Double, lngSpan: Double)

object TestData {

  /**
   * US cities with verified downtown coordinates targeting high-surveillance areas.
   *
   * Each city was chosen because its downtown has significant camera density,
   * producing realistic query results. The coordinates point to specific
   * well-known locations in each city's central business district.
   */
  val cities: Seq[CityCenter] = Seq(
    CityCenter("Denver",        39.7478, -104.9995), // 16th St Mall / Union Station
    CityCenter("Los Angeles",   34.0483, -118.2530), // Pershing Square, DTLA
    CityCenter("San Francisco", 37.7946, -122.3999), // Financial District / Market & Montgomery
    CityCenter("New York",      40.7549,  -73.9840), // Midtown / 42nd & 6th Ave
    CityCenter("Boston",        42.3567,  -71.0588), // Downtown Crossing
    CityCenter("Chicago",       41.8783,  -87.6258)  // State & Madison, The Loop
  )

  /**
   * Map viewport sizes for zoom levels 10 through 15.
   *
   * Calculated for a ~400x800px mobile screen (portrait orientation) at ~40 deg N
   * latitude using standard OSM/Slippy map tile math (Mercator projection,
   * 256px tiles). Each zoom level doubles the tile count, halving the viewport span.
   *
   * | Zoom | Approx area covered   | Example                      |
   * |------|-----------------------|------------------------------|
   * |  15  | ~1.5 x 3 km           | A few city blocks            |
   * |  14  | ~3 x 6 km             | A neighborhood               |
   * |  13  | ~6 x 12 km            | A district                   |
   * |  12  | ~12 x 23 km           | A mid-size city              |
   * |  11  | ~23 x 47 km           | A large city extent          |
   * |  10  | ~47 x 93 km           | A metro region               |
   *
   * Ordered from tightest to widest so the simulation can walk through them
   * and show the performance impact of increasing viewport size.
   */
  val zoomViewports: Seq[ZoomViewport] = Seq(
    ZoomViewport(15, 0.026, 0.017),
    ZoomViewport(14, 0.053, 0.034),
    ZoomViewport(13, 0.105, 0.069),
    ZoomViewport(12, 0.210, 0.140),
    ZoomViewport(11, 0.420, 0.270),
    ZoomViewport(10, 0.840, 0.550)
  )

  /**
   * Build the Gatling session variables for a city/viewport combination.
   *
   * Centers the viewport on the city's downtown coordinates and pre-builds
   * the Overpass query body. All feeders delegate to this method.
   */
  def buildFeedEntry(city: CityCenter, viewport: ZoomViewport): Map[String, Any] = {
    val south = city.lat - viewport.latSpan / 2
    val north = city.lat + viewport.latSpan / 2
    val west  = city.lng - viewport.lngSpan / 2
    val east  = city.lng + viewport.lngSpan / 2

    Map(
      OverpassQuery.CityName  -> city.name,
      OverpassQuery.ZoomLevel -> viewport.zoom,
      OverpassQuery.QueryBody -> OverpassQuery.buildQuery(south, west, north, east)
    )
  }

  /**
   * Infinite feeder that picks a random city and random zoom level each call.
   *
   * Unlike feederForZoom (which fixes a zoom level), this is useful for
   * concurrent and stress simulations where zoom progression doesn't matter —
   * we just want a stream of realistic, varied requests.
   *
   * Produces the same session keys (cityName, zoomLevel, queryBody) so it
   * works with the existing overpassRequest definition.
   */
  val randomFeeder: Iterator[Map[String, Any]] = Iterator.continually {
    val rng = ThreadLocalRandom.current()
    buildFeedEntry(cities(rng.nextInt(cities.length)), zoomViewports(rng.nextInt(zoomViewports.length)))
  }

  /**
   * Infinite feeder weighted toward zoom levels 13-15 (~80% of picks).
   *
   * Models real app usage: most users are zoomed in to neighborhood/district
   * level (z13-z15). Only ~20% of requests come from zoomed-out views
   * (z10-z12) where users are browsing before zooming in.
   *
   * Weight distribution (matches zoomViewports order, tightest to widest):
   *   z15: 30%, z14: 25%, z13: 25%, z12: 10%, z11: 5%, z10: 5%
   */
  val weightedZoomFeeder: Iterator[Map[String, Any]] = {
    // Weights parallel zoomViewports order (z15 first, z10 last).
    val weights = Seq(6, 5, 5, 2, 1, 1)
    val weightedPool: IndexedSeq[ZoomViewport] =
      zoomViewports.zip(weights).flatMap { case (vp, count) => Seq.fill(count)(vp) }.toIndexedSeq

    Iterator.continually {
      val rng = ThreadLocalRandom.current()
      buildFeedEntry(cities(rng.nextInt(cities.length)), weightedPool(rng.nextInt(weightedPool.length)))
    }
  }
}
