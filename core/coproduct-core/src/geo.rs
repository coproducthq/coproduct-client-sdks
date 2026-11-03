//! Geographic distance math for geo-fence targeting.
//!
//! Dependency-free so the same formula can be mirrored exactly in the platform's
//! TypeScript evaluator. Distances use the haversine great-circle formula over a
//! spherical Earth, which is accurate to well under a percent at the city/venue
//! radii geo-fence targeting uses.

/// Mean Earth radius in meters (IUGG arithmetic mean radius R1). A single sphere
/// radius keeps the formula identical across the Rust core and the TS evaluator;
/// the sub-percent error of a spherical model is immaterial at targeting radii.
const EARTH_RADIUS_METERS: f64 = 6_371_008.8;

/// Great-circle distance in meters between two WGS-84 points given in degrees.
pub fn haversine_meters(lat1: f64, lng1: f64, lat2: f64, lng2: f64) -> f64 {
    let phi1 = lat1.to_radians();
    let phi2 = lat2.to_radians();
    let delta_phi = (lat2 - lat1).to_radians();
    let delta_lambda = (lng2 - lng1).to_radians();

    let a = (delta_phi / 2.0).sin().powi(2)
        + phi1.cos() * phi2.cos() * (delta_lambda / 2.0).sin().powi(2);
    let c = 2.0 * a.sqrt().atan2((1.0 - a).sqrt());
    EARTH_RADIUS_METERS * c
}
