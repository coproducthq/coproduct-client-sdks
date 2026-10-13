// One purchase option a paywall offers, e.g. monthly or annual. packageKey
// matches the backend's abstract key; native resolves it to a real store
// product id via the sibling PaywallPackageRef map, never from this type
// directly.
export interface PaywallCta {
  packageKey: string;
  label: string;
}

function parsePaywallCta(json: Record<string, unknown>): PaywallCta {
  return {
    packageKey: json.packageKey as string,
    label: json.label as string,
  };
}

// A paywall's authored content. html is author-written markup, not
// assembled from structured fields.
export interface PaywallContent {
  offeringKey: string;
  ctas: PaywallCta[];
  html: string;
}

function parsePaywallContent(json: Record<string, unknown>): PaywallContent {
  const ctas = json.ctas as unknown[];
  return {
    offeringKey: json.offeringKey as string,
    ctas: ctas.map((c) => parsePaywallCta(c as Record<string, unknown>)),
    html: json.html as string,
  };
}

// One packageKey's store product ids, as resolved server-side from the
// offering the paywall's content.offeringKey points at. Every field is
// optional -- an offering may only have an iOS product configured, which
// this P1 is the only platform that reads.
export interface PaywallPackageRef {
  iosProductId?: string;
  androidProductId?: string;
  webProductId?: string;
}

function parsePaywallPackageRef(
  json: Record<string, unknown>
): PaywallPackageRef {
  return {
    iosProductId: json.iosProductId as string | undefined,
    androidProductId: json.androidProductId as string | undefined,
    webProductId: json.webProductId as string | undefined,
  };
}

// The resolved paywall a device fetches, mirroring
// sdks/flutter/coproduct/lib/src/paywall/models/paywall_snapshot.dart
// field for field, including the packages map the resolve step projects
// from the offering alongside content and html.
export interface PaywallSnapshot {
  paywallId: string;
  version: number;
  templateType: string;
  content: PaywallContent;
  packages: Record<string, PaywallPackageRef>;
  html: string;
}

export function parsePaywallSnapshot(
  json: Record<string, unknown>
): PaywallSnapshot {
  const packagesJson = json.packages as Record<string, unknown>;
  const packages: Record<string, PaywallPackageRef> = {};
  for (const [key, value] of Object.entries(packagesJson)) {
    packages[key] = parsePaywallPackageRef(value as Record<string, unknown>);
  }
  return {
    paywallId: json.paywallId as string,
    version: json.version as number,
    templateType: json.templateType as string,
    content: parsePaywallContent(json.content as Record<string, unknown>),
    packages,
    html: json.html as string,
  };
}
