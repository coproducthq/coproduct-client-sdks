/// One purchase option a paywall offers, e.g. monthly or annual. packageKey
/// matches the backend's abstract key (@coproduct/snapshot-spec's
/// PaywallCta) -- native resolves it to a real store product id via the
/// sibling [PaywallPackageRef] map, never from this type directly.
class PaywallCta {
  final String packageKey;
  final String label;

  const PaywallCta({required this.packageKey, required this.label});

  factory PaywallCta.fromJson(Map<String, dynamic> json) => PaywallCta(
    packageKey: json['packageKey'] as String,
    label: json['label'] as String,
  );
}

/// A paywall's authored content, mirroring @coproduct/snapshot-spec's
/// PaywallContent. html is author-written markup (the same model
/// coproduct_onboarding's Screen.html already uses), not assembled from
/// structured fields -- this package never reads content.html directly,
/// since PaywallSnapshot.html already carries the identical string at the
/// top level for the WebView to load.
class PaywallContent {
  final String offeringKey;
  final List<PaywallCta> ctas;
  final String html;

  const PaywallContent({
    required this.offeringKey,
    required this.ctas,
    required this.html,
  });

  factory PaywallContent.fromJson(Map<String, dynamic> json) => PaywallContent(
    offeringKey: json['offeringKey'] as String,
    ctas: (json['ctas'] as List)
        .map((cta) => PaywallCta.fromJson(cta as Map<String, dynamic>))
        .toList(),
    html: json['html'] as String,
  );
}

/// One packageKey's store product ids, as resolved server-side from the
/// offering the paywall's content.offeringKey points at. Every field is
/// optional -- an offering may only have an iOS product configured, which
/// this P1 is the only platform that reads.
class PaywallPackageRef {
  final String? iosProductId;
  final String? androidProductId;
  final String? webProductId;

  const PaywallPackageRef({
    this.iosProductId,
    this.androidProductId,
    this.webProductId,
  });

  factory PaywallPackageRef.fromJson(Map<String, dynamic> json) =>
      PaywallPackageRef(
        iosProductId: json['iosProductId'] as String?,
        androidProductId: json['androidProductId'] as String?,
        webProductId: json['webProductId'] as String?,
      );
}

/// The resolved paywall a device fetches from GET /paywalls/:paywallId,
/// mirroring @coproduct/snapshot-spec's PaywallSnapshot exactly, field for
/// field, including the packages map the resolve step projects from the
/// offering alongside content and html.
class PaywallSnapshot {
  final String paywallId;
  final int version;
  final String templateType;
  final PaywallContent content;
  final Map<String, PaywallPackageRef> packages;
  final String html;

  const PaywallSnapshot({
    required this.paywallId,
    required this.version,
    required this.templateType,
    required this.content,
    required this.packages,
    required this.html,
  });

  factory PaywallSnapshot.fromJson(Map<String, dynamic> json) =>
      PaywallSnapshot(
        paywallId: json['paywallId'] as String,
        version: json['version'] as int,
        templateType: json['templateType'] as String,
        content: PaywallContent.fromJson(
          json['content'] as Map<String, dynamic>,
        ),
        packages: (json['packages'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(
            key,
            PaywallPackageRef.fromJson(value as Map<String, dynamic>),
          ),
        ),
        html: json['html'] as String,
      );
}
