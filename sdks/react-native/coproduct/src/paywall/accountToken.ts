/* eslint-disable no-bitwise */

// The namespace the Coproduct server derives store account tokens under,
// 8f1b6c1e-6f0a-4d0e-9a53-2c1d7f4b9e10, as bytes. Must match the server and
// every other SDK exactly, or the server cannot tell whose purchase it is.
const ACCOUNT_TOKEN_NAMESPACE = [
  0x8f, 0x1b, 0x6c, 0x1e, 0x6f, 0x0a, 0x4d, 0x0e, 0x9a, 0x53, 0x2c, 0x1d, 0x7f,
  0x4b, 0x9e, 0x10,
];

// Encoded by hand rather than through TextEncoder, so the token does not
// depend on which globals the host JS engine happens to provide.
function utf8Bytes(text: string): number[] {
  const bytes: number[] = [];
  for (const char of text) {
    let codePoint = char.codePointAt(0) ?? 0xfffd;
    // A lone surrogate has no UTF-8 form; encode the replacement character
    if (codePoint >= 0xd800 && codePoint <= 0xdfff) codePoint = 0xfffd;
    if (codePoint < 0x80) {
      bytes.push(codePoint);
    } else if (codePoint < 0x800) {
      bytes.push(0xc0 | (codePoint >> 6), 0x80 | (codePoint & 0x3f));
    } else if (codePoint < 0x10000) {
      bytes.push(
        0xe0 | (codePoint >> 12),
        0x80 | ((codePoint >> 6) & 0x3f),
        0x80 | (codePoint & 0x3f)
      );
    } else {
      bytes.push(
        0xf0 | (codePoint >> 18),
        0x80 | ((codePoint >> 12) & 0x3f),
        0x80 | ((codePoint >> 6) & 0x3f),
        0x80 | (codePoint & 0x3f)
      );
    }
  }
  return bytes;
}

function rotateLeft(value: number, bits: number): number {
  return (value << bits) | (value >>> (32 - bits));
}

// SHA-1 (FIPS 180-4), returning the 20-byte digest. Written out here because
// React Native ships no hash function and this package may not take a
// dependency for one. SHA-1 is what a version 5 UUID is defined over; nothing
// here relies on it for security.
function sha1(message: number[]): DataView {
  const paddedLength = (((message.length + 8) >> 6) + 1) << 6;
  const padded = new DataView(new ArrayBuffer(paddedLength));
  message.forEach((byte, index) => padded.setUint8(index, byte));
  padded.setUint8(message.length, 0x80);
  // The message length in bits, as a 64-bit big-endian integer
  padded.setUint32(paddedLength - 8, Math.floor(message.length / 0x20000000));
  padded.setUint32(paddedLength - 4, message.length << 3);

  const digest = new DataView(new ArrayBuffer(20));
  [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0].forEach(
    (word, index) => digest.setUint32(index * 4, word)
  );

  const schedule = new DataView(new ArrayBuffer(320));
  for (let offset = 0; offset < paddedLength; offset += 64) {
    for (let t = 0; t < 80; t++) {
      schedule.setUint32(
        t * 4,
        t < 16
          ? padded.getUint32(offset + t * 4)
          : rotateLeft(
              schedule.getUint32((t - 3) * 4) ^
                schedule.getUint32((t - 8) * 4) ^
                schedule.getUint32((t - 14) * 4) ^
                schedule.getUint32((t - 16) * 4),
              1
            )
      );
    }

    let a = digest.getUint32(0);
    let b = digest.getUint32(4);
    let c = digest.getUint32(8);
    let d = digest.getUint32(12);
    let e = digest.getUint32(16);
    for (let t = 0; t < 80; t++) {
      let f: number;
      let k: number;
      if (t < 20) {
        f = (b & c) | (~b & d);
        k = 0x5a827999;
      } else if (t < 40) {
        f = b ^ c ^ d;
        k = 0x6ed9eba1;
      } else if (t < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8f1bbcdc;
      } else {
        f = b ^ c ^ d;
        k = 0xca62c1d6;
      }
      const next =
        (rotateLeft(a, 5) + f + e + k + schedule.getUint32(t * 4)) | 0;
      e = d;
      d = c;
      c = rotateLeft(b, 30);
      b = a;
      a = next;
    }
    digest.setUint32(0, digest.getUint32(0) + a);
    digest.setUint32(4, digest.getUint32(4) + b);
    digest.setUint32(8, digest.getUint32(8) + c);
    digest.setUint32(12, digest.getUint32(12) + d);
    digest.setUint32(16, digest.getUint32(16) + e);
  }
  return digest;
}

/**
 * The store account token for an app user: a version 5 UUID (RFC 4122, SHA-1)
 * of the app user id's UTF-8 bytes under Coproduct's namespace, in lowercase
 * hyphenated form. The store keeps it with the transaction (StoreKit's
 * appAccountToken, Play's obfuscatedAccountId) and the server recomputes it to
 * learn which app user a purchase was made for.
 *
 * Internal: not exported from the package's paywall entrypoint.
 */
export function accountToken(appUserId: string): string {
  const digest = sha1([...ACCOUNT_TOKEN_NAMESPACE, ...utf8Bytes(appUserId)]);
  const hex: string[] = [];
  for (let index = 0; index < 16; index++) {
    let byte = digest.getUint8(index);
    if (index === 6) byte = (byte & 0x0f) | 0x50;
    if (index === 8) byte = (byte & 0x3f) | 0x80;
    hex.push(byte.toString(16).padStart(2, '0'));
  }
  return [
    hex.slice(0, 4).join(''),
    hex.slice(4, 6).join(''),
    hex.slice(6, 8).join(''),
    hex.slice(8, 10).join(''),
    hex.slice(10, 16).join(''),
  ].join('-');
}
