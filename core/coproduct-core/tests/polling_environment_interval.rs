use coproduct_core::polling::{NON_PRODUCTION_POLL_INTERVAL, poll_interval_for_environment};
use std::time::Duration;

const CONFIGURED: Duration = Duration::from_secs(60);

#[test]
fn non_production_interval_is_two_seconds() {
    assert_eq!(NON_PRODUCTION_POLL_INTERVAL, Duration::from_secs(2));
}

#[test]
fn development_and_staging_poll_every_two_seconds() {
    for slug in ["development", "staging"] {
        assert_eq!(
            poll_interval_for_environment(CONFIGURED, slug),
            NON_PRODUCTION_POLL_INTERVAL,
            "slug {slug} should poll at the non-production interval"
        );
    }
}

#[test]
fn slug_match_ignores_case_and_surrounding_whitespace() {
    assert_eq!(
        poll_interval_for_environment(CONFIGURED, " Staging "),
        NON_PRODUCTION_POLL_INTERVAL
    );
    assert_eq!(
        poll_interval_for_environment(CONFIGURED, "DEVELOPMENT"),
        NON_PRODUCTION_POLL_INTERVAL
    );
}

#[test]
fn production_keeps_the_configured_interval() {
    assert_eq!(
        poll_interval_for_environment(CONFIGURED, "production"),
        CONFIGURED
    );
    assert_eq!(
        poll_interval_for_environment(Duration::from_secs(30), "production"),
        Duration::from_secs(30)
    );
}

#[test]
fn unknown_and_empty_slugs_keep_the_configured_interval() {
    for slug in [
        "",
        "dev",
        "stage",
        "qa",
        "preview",
        "development-eu",
        "prod",
    ] {
        assert_eq!(
            poll_interval_for_environment(CONFIGURED, slug),
            CONFIGURED,
            "slug {slug:?} should keep the configured interval"
        );
    }
}

mod client {
    use super::CONFIGURED;
    use async_trait::async_trait;
    use coproduct_core::client::CoproductClient;
    use coproduct_core::config::CoproductConfig;
    use coproduct_core::polling::{NON_PRODUCTION_POLL_INTERVAL, PollOutcome};
    use coproduct_core::secure_store::{SecureStore, SecureStoreError};
    use coproduct_core::transport::{HttpRequest, HttpResponse, Transport, TransportError};
    use parking_lot::Mutex;
    use std::collections::HashMap;
    use std::sync::Arc;
    use tempfile::TempDir;

    #[derive(Debug)]
    struct SnapshotTransport {
        slug: &'static str,
    }

    #[async_trait]
    impl Transport for SnapshotTransport {
        async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
            let body = format!(
                r#"{{"snapshot":{{"schemaVersion":1,"version":1,"generatedAt":"2026-06-02T00:00:00Z","environment":{{"slug":"{}","projectKey":"my-app"}},"flags":[],"segments":[]}}}}"#,
                self.slug
            );
            Ok(HttpResponse {
                status: 200,
                body: body.into_bytes(),
                headers: Vec::new(),
            })
        }
    }

    #[derive(Debug, Default)]
    struct InMemorySecureStore {
        inner: Mutex<HashMap<String, String>>,
    }

    #[async_trait]
    impl SecureStore for InMemorySecureStore {
        async fn read(&self, key: String) -> Result<Option<String>, SecureStoreError> {
            Ok(self.inner.lock().get(&key).cloned())
        }
        async fn write(&self, key: String, value: String) -> Result<(), SecureStoreError> {
            self.inner.lock().insert(key, value);
            Ok(())
        }
    }

    fn client_for(slug: &'static str, dir: &TempDir) -> Arc<CoproductClient> {
        futures::executor::block_on(CoproductClient::initialize(
            "cpk_mob_envtestaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(),
            "coproduct-ios/test".to_string(),
            CoproductConfig::default(),
            dir.path().to_string_lossy().into_owned(),
            Arc::new(SnapshotTransport { slug }),
            Arc::new(InMemorySecureStore::default()),
        ))
        .expect("initialize")
    }

    #[test]
    fn keeps_the_configured_interval_before_any_snapshot_loads() {
        let dir = TempDir::new().unwrap();
        let client = client_for("staging", &dir);
        assert_eq!(client.effective_poll_interval(CONFIGURED), CONFIGURED);
    }

    #[test]
    fn shortens_to_two_seconds_once_a_staging_snapshot_loads() {
        let dir = TempDir::new().unwrap();
        let client = client_for("staging", &dir);
        assert_eq!(
            futures::executor::block_on(client.poll_now()),
            PollOutcome::Updated
        );
        assert_eq!(
            client.effective_poll_interval(CONFIGURED),
            NON_PRODUCTION_POLL_INTERVAL
        );
    }

    #[test]
    fn shortens_to_two_seconds_from_a_cached_development_snapshot() {
        let dir = TempDir::new().unwrap();
        let first = client_for("development", &dir);
        futures::executor::block_on(first.poll_now());
        futures::executor::block_on(first.shutdown());

        // A relaunch reads the cached snapshot at initialize, so the first
        // scheduled poll already runs at the fast cadence
        let relaunched = client_for("development", &dir);
        assert_eq!(
            relaunched.effective_poll_interval(CONFIGURED),
            NON_PRODUCTION_POLL_INTERVAL
        );
    }

    #[test]
    fn keeps_the_configured_interval_for_a_production_snapshot() {
        let dir = TempDir::new().unwrap();
        let client = client_for("production", &dir);
        assert_eq!(
            futures::executor::block_on(client.poll_now()),
            PollOutcome::Updated
        );
        assert_eq!(client.effective_poll_interval(CONFIGURED), CONFIGURED);
    }
}
