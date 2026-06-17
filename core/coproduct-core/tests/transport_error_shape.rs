use coproduct_core::error::TransportError;

#[test]
fn server_error_carries_status_code() {
    let err = TransportError::ServerError { status: 503 };
    let rendered = format!("{err}");
    assert!(rendered.contains("503"));
}

#[test]
fn unauthorized_is_distinct_from_server_error() {
    let unauth = TransportError::Unauthorized;
    let server = TransportError::ServerError { status: 401 };
    assert_ne!(format!("{unauth}"), format!("{server}"));
}

#[test]
fn other_carries_host_supplied_message() {
    let err = TransportError::Other {
        message: "TLS handshake aborted".into(),
    };
    let rendered = format!("{err}");
    assert!(rendered.contains("TLS handshake aborted"));
}

#[test]
fn timeout_network_unreachable_malformed_render() {
    for err in [
        TransportError::Timeout,
        TransportError::NetworkUnreachable,
        TransportError::MalformedResponse,
    ] {
        let rendered = format!("{err}");
        assert!(!rendered.is_empty());
    }
}
