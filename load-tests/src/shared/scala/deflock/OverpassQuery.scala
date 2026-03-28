package deflock

import scala.concurrent.duration._

/**
 * Pure Overpass API query logic — no Gatling dependency.
 *
 * Contains the query builder, tag filters, timeouts, and feeder session
 * key constants. The Gatling HTTP request definition that uses these lives
 * in OverpassRequests (in the gatling source set).
 */
object OverpassQuery {

  // --- Timeouts ---
  // The Overpass QL query tells the server to abort after this many seconds.
  // This matches kOverpassQueryTimeout in the app (lib/dev_config.dart).
  val serverTimeoutSeconds = 45

  // The HTTP client timeout is slightly longer than the server timeout so that
  // we always receive the server's own timeout error response (a 200 with a
  // "remark" field) rather than the client aborting the connection first.
  val clientTimeout: FiniteDuration = (serverTimeoutSeconds + 5).seconds

  // --- Overpass tag filters ---
  // One entry per built-in NodeProfile in the app (lib/models/node_profile.dart).
  // Each string is the concatenated tag filters for that profile, with empty
  // values (e.g., camera:mount='') filtered out — exactly as the app's
  // OverpassService._buildQuery() does. Keep this list in sync with
  // NodeProfile.getDefaults().
  val tagFilters: Seq[String] = Seq(
    // generic-alpr
    """["man_made"="surveillance"]["surveillance:type"="ALPR"]""",
    // flock
    """["man_made"="surveillance"]["surveillance"="public"]["surveillance:type"="ALPR"]["surveillance:zone"="traffic"]["camera:type"="fixed"]["manufacturer"="Flock Safety"]["manufacturer:wikidata"="Q108485435"]""",
    // motorola
    """["man_made"="surveillance"]["surveillance"="public"]["surveillance:type"="ALPR"]["surveillance:zone"="traffic"]["camera:type"="fixed"]["manufacturer"="Motorola Solutions"]["manufacturer:wikidata"="Q634815"]""",
    // genetec
    """["man_made"="surveillance"]["surveillance"="public"]["surveillance:type"="ALPR"]["surveillance:zone"="traffic"]["camera:type"="fixed"]["manufacturer"="Genetec"]["manufacturer:wikidata"="Q30295174"]""",
    // leonardo
    """["man_made"="surveillance"]["surveillance"="public"]["surveillance:type"="ALPR"]["surveillance:zone"="traffic"]["camera:type"="fixed"]["manufacturer"="Leonardo"]["manufacturer:wikidata"="Q910379"]""",
    // neology
    """["man_made"="surveillance"]["surveillance"="public"]["surveillance:type"="ALPR"]["surveillance:zone"="traffic"]["camera:type"="fixed"]["manufacturer"="Neology, Inc."]""",
    // rekor
    """["man_made"="surveillance"]["surveillance"="public"]["surveillance:type"="ALPR"]["surveillance:zone"="traffic"]["camera:type"="fixed"]["manufacturer"="Rekor"]""",
    // axis
    """["man_made"="surveillance"]["surveillance"="public"]["surveillance:type"="ALPR"]["surveillance:zone"="traffic"]["camera:type"="fixed"]["manufacturer"="Axis Communications"]["manufacturer:wikidata"="Q2347731"]""",
    // generic-gunshot
    """["man_made"="surveillance"]["surveillance:type"="gunshot_detector"]""",
    // shotspotter
    """["man_made"="surveillance"]["surveillance"="public"]["surveillance:type"="gunshot_detector"]["surveillance:brand"="ShotSpotter"]["surveillance:brand:wikidata"="Q107740188"]""",
    // flock-raven
    """["man_made"="surveillance"]["surveillance"="public"]["surveillance:type"="gunshot_detector"]["brand"="Flock Safety"]["brand:wikidata"="Q108485435"]"""
  )

  // --- Feeder session keys ---
  // These constants are the variable names injected into each virtual user's
  // session by the feeders in TestData. Using constants here (instead of raw
  // strings) prevents typos that would silently break at runtime.
  val CityName  = "cityName"
  val ZoomLevel = "zoomLevel"
  val QueryBody = "queryBody"

  /**
   * Build an Overpass QL query string for the given bounding box.
   *
   * The query structure mirrors the app's OverpassService._buildQuery():
   * union node clauses in a bbox, then fetch parent ways/relations. Uses
   * the same per-profile tag filters as the app (see tagFilters above).
   *
   * Overpass bbox format is (south, west, north, east) — note this is
   * different from many mapping libraries that use (west, south, east, north).
   *
   * @return A complete Overpass QL query string ready to POST
   */
  def buildQuery(south: Double, west: Double, north: Double, east: Double): String = {
    val nodeClauses = tagFilters.map { tags =>
      s"  node$tags($south,$west,$north,$east);"
    }.mkString("\n")

    s"""[out:json][timeout:$serverTimeoutSeconds];
       |(
       |$nodeClauses
       |);
       |out body;
       |(
       |  way(bn);
       |  rel(bn);
       |);
       |out skel;""".stripMargin
  }
}
