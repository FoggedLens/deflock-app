// Gatling load test build configuration.
//
// Gatling (https://gatling.io) is a load testing framework that simulates
// virtual users sending HTTP requests and produces HTML performance reports.
//
// The `scala` plugin compiles our Scala simulation files.
// The `io.gatling.gradle` plugin adds the `gatlingRun` task and manages
// Gatling + Scala library dependencies automatically.
//
// Run simulations:  ./gradlew gatlingRun
// Run unit tests:   ./gradlew test
// Reports:          build/reports/gatling/

plugins {
    scala
    id("io.gatling.gradle") version "3.15.0"
}

repositories {
    mavenCentral()
}

// --- Source sets ---
// "shared" contains pure Scala logic (TestData, OverpassQuery) with no Gatling
// dependency. Both the "gatling" source set (simulations) and "test" source set
// (unit tests) depend on it. This avoids the circular dependency that would
// occur if tests depended directly on the gatling source set (since the Gatling
// plugin makes gatling extend test).

sourceSets {
    create("shared")
}

dependencies {
    // shared source set needs Scala stdlib (provided transitively by Gatling,
    // but shared compiles independently)
    "sharedImplementation"("org.scala-lang:scala-library:2.13.16")

    // Gatling simulations use shared logic
    "gatlingImplementation"(sourceSets["shared"].output)

    // Unit tests use shared logic + ScalaTest
    testImplementation(sourceSets["shared"].output)
    testImplementation("org.scalatest:scalatest_2.13:3.2.19")
    testImplementation("org.scalatestplus:junit-5-11_2.13:3.2.19.0")
    testRuntimeOnly("org.junit.jupiter:junit-jupiter-engine:5.11.4")
}

tasks.withType<Test> {
    useJUnitPlatform()
}
