package deflock

import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers

class TestDataSpec extends AnyFlatSpec with Matchers {

  // --- Test data constants ---

  "cities" should "contain 6 entries" in {
    TestData.cities should have length 6
  }

  it should "have unique names" in {
    val names = TestData.cities.map(_.name)
    names.distinct should have length names.length.toLong
  }

  it should "have valid coordinates (US mainland)" in {
    TestData.cities.foreach { city =>
      city.lat should (be >= 24.0 and be <= 50.0)
      city.lng should (be >= -125.0 and be <= -66.0)
    }
  }

  "zoomViewports" should "cover zoom levels 10-15" in {
    TestData.zoomViewports.map(_.zoom).sorted shouldBe Seq(10, 11, 12, 13, 14, 15)
  }

  it should "have spans that grow as zoom decreases (wider view)" in {
    val sortedByZoom = TestData.zoomViewports.sortBy(_.zoom)
    sortedByZoom.sliding(2).foreach { case Seq(wider, tighter) =>
      wider.latSpan should be > tighter.latSpan
      wider.lngSpan should be > tighter.lngSpan
    }
  }

  it should "have roughly 2x span increase per zoom level" in {
    val sortedByZoom = TestData.zoomViewports.sortBy(_.zoom)
    sortedByZoom.sliding(2).foreach { case Seq(wider, tighter) =>
      val latRatio = wider.latSpan / tighter.latSpan
      latRatio should (be >= 1.8 and be <= 2.2)
    }
  }

  // --- buildFeedEntry ---

  "buildFeedEntry" should "produce all required session keys" in {
    val city = CityCenter("Test", 40.0, -74.0)
    val viewport = ZoomViewport(15, 0.026, 0.017)
    val entry = TestData.buildFeedEntry(city, viewport)

    entry should contain key OverpassQuery.CityName
    entry should contain key OverpassQuery.ZoomLevel
    entry should contain key OverpassQuery.QueryBody
  }

  it should "set cityName and zoomLevel from inputs" in {
    val city = CityCenter("Denver", 39.7478, -104.9995)
    val viewport = ZoomViewport(13, 0.105, 0.069)
    val entry = TestData.buildFeedEntry(city, viewport)

    entry(OverpassQuery.CityName) shouldBe "Denver"
    entry(OverpassQuery.ZoomLevel) shouldBe 13
  }

  it should "center the bounding box on the city coordinates" in {
    val city = CityCenter("Test", 40.0, -74.0)
    val viewport = ZoomViewport(15, 0.026, 0.017)
    val entry = TestData.buildFeedEntry(city, viewport)
    val query = entry(OverpassQuery.QueryBody).asInstanceOf[String]

    // south = 40.0 - 0.013 = 39.987, north = 40.0 + 0.013 = 40.013
    // west = -74.0 - 0.0085 = -74.0085, east = -74.0 + 0.0085 = -73.9915
    query should include ("39.987")
    query should include ("40.013")
    query should include ("-74.0085")
    query should include ("-73.9915")
  }

  // --- randomFeeder ---

  "randomFeeder" should "produce valid entries on each call" in {
    val entries = (1 to 20).map(_ => TestData.randomFeeder.next())

    entries.foreach { entry =>
      entry should contain key OverpassQuery.CityName
      entry should contain key OverpassQuery.ZoomLevel
      entry should contain key OverpassQuery.QueryBody
      TestData.cities.map(_.name) should contain (entry(OverpassQuery.CityName))
      TestData.zoomViewports.map(_.zoom) should contain (entry(OverpassQuery.ZoomLevel))
    }
  }

  it should "produce varied results (not always the same)" in {
    val entries = (1 to 50).map(_ => TestData.randomFeeder.next())
    val uniqueCities = entries.map(_(OverpassQuery.CityName)).distinct
    val uniqueZooms = entries.map(_(OverpassQuery.ZoomLevel)).distinct

    uniqueCities.length should be > 1
    uniqueZooms.length should be > 1
  }

  // --- weightedZoomFeeder ---

  "weightedZoomFeeder" should "produce valid entries" in {
    val entries = (1 to 20).map(_ => TestData.weightedZoomFeeder.next())

    entries.foreach { entry =>
      entry should contain key OverpassQuery.CityName
      entry should contain key OverpassQuery.ZoomLevel
      entry should contain key OverpassQuery.QueryBody
    }
  }

  it should "favor zoom levels 13-15 over 10-12" in {
    val entries = (1 to 1000).map(_ => TestData.weightedZoomFeeder.next())
    val zooms = entries.map(_(OverpassQuery.ZoomLevel).asInstanceOf[Int])

    val closeZooms = zooms.count(z => z >= 13 && z <= 15)
    val farZooms = zooms.count(z => z >= 10 && z <= 12)

    // 80% should be z13-z15, 20% z10-z12. Allow some variance.
    closeZooms.toDouble / entries.length should be > 0.65
    farZooms.toDouble / entries.length should be < 0.35
  }
}
