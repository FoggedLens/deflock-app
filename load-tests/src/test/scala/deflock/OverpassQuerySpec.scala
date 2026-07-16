package deflock

import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers

class OverpassQuerySpec extends AnyFlatSpec with Matchers {

  "buildQuery" should "include the server timeout" in {
    val query = OverpassQuery.buildQuery(39.0, -105.0, 40.0, -104.0)
    query should include (s"[timeout:${OverpassQuery.serverTimeoutSeconds}]")
  }

  it should "request JSON output" in {
    val query = OverpassQuery.buildQuery(39.0, -105.0, 40.0, -104.0)
    query should include ("[out:json]")
  }

  it should "include the bounding box in Overpass order (south,west,north,east)" in {
    val query = OverpassQuery.buildQuery(39.0, -105.0, 40.0, -104.0)
    query should include ("(39.0,-105.0,40.0,-104.0)")
  }

  it should "include all configured tag filters" in {
    val query = OverpassQuery.buildQuery(39.0, -105.0, 40.0, -104.0)
    OverpassQuery.tagFilters.foreach { filter =>
      query should include (filter)
    }
  }

  it should "include parent way and relation lookups" in {
    val query = OverpassQuery.buildQuery(39.0, -105.0, 40.0, -104.0)
    query should include ("way(bn)")
    query should include ("rel(bn)")
  }

  it should "end with out skel for parent geometry" in {
    val query = OverpassQuery.buildQuery(39.0, -105.0, 40.0, -104.0)
    query should endWith ("out skel;")
  }

  "tagFilters" should "have one entry per app profile (11 built-in profiles)" in {
    OverpassQuery.tagFilters should have size 11
  }

  it should "all start with man_made=surveillance" in {
    every(OverpassQuery.tagFilters) should include ("""["man_made"="surveillance"]""")
  }

  "serverTimeoutSeconds" should "be positive" in {
    OverpassQuery.serverTimeoutSeconds should be > 0
  }

  "clientTimeout" should "be longer than server timeout" in {
    OverpassQuery.clientTimeout.toSeconds should be > OverpassQuery.serverTimeoutSeconds.toLong
  }
}
