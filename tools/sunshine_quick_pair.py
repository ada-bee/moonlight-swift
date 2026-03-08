#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "cryptography>=44.0.0",
#   "requests>=2.32.0",
# ]
# ///

from __future__ import annotations

import argparse
import binascii
import json
import os
import random
import re
import secrets
import sys
import textwrap
import warnings
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any
from urllib.parse import urlencode
import xml.etree.ElementTree as ET

import requests
from cryptography import x509
from cryptography.hazmat.primitives import hashes, padding, serialization
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding, rsa
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.x509.oid import NameOID


DEFAULT_HTTP_PORT = 47989
DEFAULT_HTTPS_PORT = 47984
CERT_COMMON_NAME = "NVIDIA GameStream Client"


class PairingError(RuntimeError):
    pass


@dataclass
class PairingIdentity:
    unique_id: str
    certificate_pem: bytes
    private_key_pem: bytes


@dataclass
class PairingArtifacts:
    output_dir: Path
    cert_path: Path
    key_path: Path
    server_cert_path: Path
    metadata_path: Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Quick one-off Sunshine pairing helper that keeps all generated state in one easy-to-delete folder.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent(
            """
            Example:
              tools/sunshine_quick_pair.py 192.168.1.10 --name lean-debug

            The script will:
            1. generate a temporary Moonlight-style client certificate and unique ID
            2. print a 4-digit PIN for you to enter in Sunshine
            3. finish the full pairing handshake over Sunshine's /pair endpoint
            4. write the generated cert/key/server-cert/metadata into one folder
            """
        ),
    )
    parser.add_argument("host", help="Sunshine host address or hostname")
    parser.add_argument(
        "--name",
        default="lean-debug",
        help="Friendly device name to use when prompted in Sunshine",
    )
    parser.add_argument(
        "--pin", help="Optional fixed 4-digit PIN; otherwise one is generated"
    )
    parser.add_argument(
        "--http-port",
        type=int,
        default=DEFAULT_HTTP_PORT,
        help=f"Sunshine HTTP pairing port (default: {DEFAULT_HTTP_PORT})",
    )
    parser.add_argument(
        "--https-port", type=int, help="Optional Sunshine HTTPS port override"
    )
    parser.add_argument(
        "--output-dir",
        default="tools/.quick-pair",
        help="Directory where generated pairing state is stored",
    )
    parser.add_argument(
        "--request-timeout",
        type=float,
        default=300.0,
        help="Read timeout in seconds while waiting for Sunshine PIN approval",
    )
    parser.add_argument(
        "--skip-verify-check",
        action="store_true",
        help="Skip post-pair HTTPS verification request",
    )
    return parser.parse_args()


def generate_identity() -> PairingIdentity:
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = issuer = x509.Name(
        [
            x509.NameAttribute(NameOID.COMMON_NAME, CERT_COMMON_NAME),
        ]
    )

    certificate = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(private_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(datetime.now(UTC) - timedelta(minutes=1))
        .not_valid_after(datetime.now(UTC) + timedelta(days=365 * 20))
        .sign(private_key, hashes.SHA256())
    )

    certificate_pem = certificate.public_bytes(serialization.Encoding.PEM)
    private_key_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.TraditionalOpenSSL,
        encryption_algorithm=serialization.NoEncryption(),
    )

    unique_id = f"{secrets.randbits(64):016x}"
    return PairingIdentity(
        unique_id=unique_id,
        certificate_pem=certificate_pem,
        private_key_pem=private_key_pem,
    )


def build_output_paths(base_dir: Path, host: str) -> PairingArtifacts:
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", host).strip("-") or "sunshine-host"
    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    output_dir = base_dir / f"{slug}-{stamp}"
    return PairingArtifacts(
        output_dir=output_dir,
        cert_path=output_dir / "client-cert.pem",
        key_path=output_dir / "client-key.pem",
        server_cert_path=output_dir / "server-cert.pem",
        metadata_path=output_dir / "pairing.json",
    )


def random_pin() -> str:
    return f"{random.randint(0, 9999):04d}"


def random_uuid_hex() -> str:
    return secrets.token_hex(16)


def hex_encode(data: bytes) -> str:
    return binascii.hexlify(data).decode("ascii")


def hex_decode(value: str) -> bytes:
    return binascii.unhexlify(value.encode("ascii"))


def aes_key_from_salt_and_pin(salt: bytes, pin: str) -> bytes:
    digest = hashes.Hash(hashes.SHA256())
    digest.update(salt)
    digest.update(pin.encode("ascii"))
    return digest.finalize()[:16]


def aes_ecb_encrypt(key: bytes, plaintext: bytes) -> bytes:
    if len(plaintext) % 16 != 0:
        raise PairingError(
            f"AES-ECB plaintext must be 16-byte aligned, got {len(plaintext)} bytes"
        )
    encryptor = Cipher(algorithms.AES(key), modes.ECB()).encryptor()
    return encryptor.update(plaintext) + encryptor.finalize()


def aes_ecb_decrypt(key: bytes, ciphertext: bytes) -> bytes:
    if len(ciphertext) % 16 != 0:
        raise PairingError(
            f"AES-ECB ciphertext must be 16-byte aligned, got {len(ciphertext)} bytes"
        )
    decryptor = Cipher(algorithms.AES(key), modes.ECB()).decryptor()
    return decryptor.update(ciphertext) + decryptor.finalize()


def sha256_bytes(*parts: bytes) -> bytes:
    digest = hashes.Hash(hashes.SHA256())
    for part in parts:
        digest.update(part)
    return digest.finalize()


def parse_xml(xml_text: str) -> ET.Element:
    try:
        return ET.fromstring(xml_text)
    except ET.ParseError as exc:
        raise PairingError(f"Malformed XML response: {exc}") from exc


def response_status(root: ET.Element) -> tuple[int | None, str | None]:
    return (
        int(root.attrib["status_code"]) if "status_code" in root.attrib else None,
        root.attrib.get("status_message"),
    )


def require_ok(root: ET.Element, action: str) -> None:
    status_code, status_message = response_status(root)
    if status_code != 200:
        raise PairingError(
            f"{action} failed: status_code={status_code} status_message={status_message!r}"
        )


def child_text(root: ET.Element, name: str) -> str | None:
    child = root.find(name)
    return child.text if child is not None else None


def make_http_url(host: str, port: int, path: str) -> str:
    return f"http://{host}:{port}{path}"


def make_https_url(host: str, port: int, path: str) -> str:
    return f"https://{host}:{port}{path}"


def get_serverinfo(
    session: requests.Session, host: str, port: int, unique_id: str
) -> ET.Element:
    response = session.get(
        make_http_url(host, port, "/serverinfo"),
        params={"uniqueid": unique_id, "uuid": random_uuid_hex()},
        timeout=(5, 15),
    )
    response.raise_for_status()
    root = parse_xml(response.text)
    require_ok(root, "serverinfo")
    return root


def pair_request(
    session: requests.Session,
    host: str,
    port: int,
    params: dict[str, Any],
    timeout_seconds: float,
) -> ET.Element:
    response = session.get(
        make_http_url(host, port, "/pair"),
        params=params,
        timeout=(5, timeout_seconds),
    )
    response.raise_for_status()
    root = parse_xml(response.text)
    require_ok(root, "pair")
    return root


def verify_server_signature(
    server_cert_pem: bytes, server_secret: bytes, signature: bytes
) -> None:
    certificate = x509.load_pem_x509_certificate(server_cert_pem)
    certificate.public_key().verify(
        signature, server_secret, asym_padding.PKCS1v15(), hashes.SHA256()
    )


def sign_with_client_key(private_key_pem: bytes, payload: bytes) -> bytes:
    private_key = serialization.load_pem_private_key(private_key_pem, password=None)
    return private_key.sign(payload, asym_padding.PKCS1v15(), hashes.SHA256())


def persist_artifacts(
    artifacts: PairingArtifacts,
    identity: PairingIdentity,
    server_cert_pem: bytes,
    metadata: dict[str, Any],
) -> None:
    artifacts.output_dir.mkdir(parents=True, exist_ok=False)
    artifacts.cert_path.write_bytes(identity.certificate_pem)
    artifacts.key_path.write_bytes(identity.private_key_pem)
    artifacts.server_cert_path.write_bytes(server_cert_pem)
    artifacts.metadata_path.write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
    )


def https_verify_pairing(
    host: str,
    https_port: int,
    unique_id: str,
    cert_path: Path,
    key_path: Path,
) -> ET.Element:
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        response = requests.get(
            make_https_url(host, https_port, "/serverinfo"),
            params={"uniqueid": unique_id, "uuid": random_uuid_hex()},
            cert=(str(cert_path), str(key_path)),
            verify=False,
            timeout=(5, 15),
        )
    response.raise_for_status()
    root = parse_xml(response.text)
    require_ok(root, "https serverinfo verification")
    return root


def run() -> int:
    args = parse_args()

    if args.pin is not None and not re.fullmatch(r"\d{4}", args.pin):
        raise SystemExit("--pin must be exactly 4 digits")

    output_base = Path(args.output_dir)
    artifacts = build_output_paths(output_base, args.host)
    identity = generate_identity()
    pin = args.pin or random_pin()

    session = requests.Session()
    session.headers.update({"User-Agent": "moonlight-swift-quick-pair/0.1"})

    print(f"Host: {args.host}:{args.http_port}")
    print(f"Device name: {args.name}")
    print(f"Client unique ID: {identity.unique_id}")
    print()
    print(f"Enter this PIN into Sunshine: {pin}")
    print(f"If Sunshine asks for a device name, use: {args.name}")
    print()

    serverinfo = get_serverinfo(session, args.host, args.http_port, identity.unique_id)
    https_port = args.https_port or int(
        child_text(serverinfo, "HttpsPort") or DEFAULT_HTTPS_PORT
    )
    app_version = child_text(serverinfo, "appversion")
    gfe_version = child_text(serverinfo, "GfeVersion")
    codec_mode_support = int(child_text(serverinfo, "ServerCodecModeSupport") or "0")

    salt = os.urandom(16)
    phase1 = pair_request(
        session,
        args.host,
        args.http_port,
        {
            "uniqueid": identity.unique_id,
            "uuid": random_uuid_hex(),
            "devicename": args.name,
            "updateState": "1",
            "phrase": "getservercert",
            "salt": hex_encode(salt),
            "clientcert": hex_encode(identity.certificate_pem),
        },
        timeout_seconds=args.request_timeout,
    )

    plaincert_hex = child_text(phase1, "plaincert")
    if not plaincert_hex:
        raise PairingError(
            "Pair phase 1 succeeded but Sunshine did not return plaincert"
        )
    server_cert_pem = hex_decode(plaincert_hex)

    aes_key = aes_key_from_salt_and_pin(salt, pin)
    client_challenge = os.urandom(16)
    phase2 = pair_request(
        session,
        args.host,
        args.http_port,
        {
            "uniqueid": identity.unique_id,
            "uuid": random_uuid_hex(),
            "clientchallenge": hex_encode(aes_ecb_encrypt(aes_key, client_challenge)),
        },
        timeout_seconds=30,
    )

    challenger_response_hex = child_text(phase2, "challengeresponse")
    if not challenger_response_hex:
        raise PairingError(
            "Pair phase 2 succeeded but Sunshine did not return challengeresponse"
        )
    challenger_response = aes_ecb_decrypt(aes_key, hex_decode(challenger_response_hex))
    if len(challenger_response) < 48:
        raise PairingError(
            f"Unexpected challengeresponse length: {len(challenger_response)}"
        )
    server_hash = challenger_response[:32]
    server_challenge = challenger_response[32:48]

    client_cert_signature = x509.load_pem_x509_certificate(
        identity.certificate_pem
    ).signature
    client_secret = os.urandom(16)
    client_hash = sha256_bytes(server_challenge, client_cert_signature, client_secret)
    phase3 = pair_request(
        session,
        args.host,
        args.http_port,
        {
            "uniqueid": identity.unique_id,
            "uuid": random_uuid_hex(),
            "serverchallengeresp": hex_encode(aes_ecb_encrypt(aes_key, client_hash)),
        },
        timeout_seconds=30,
    )

    pairing_secret_hex = child_text(phase3, "pairingsecret")
    if not pairing_secret_hex:
        raise PairingError(
            "Pair phase 3 succeeded but Sunshine did not return pairingsecret"
        )
    pairing_secret = hex_decode(pairing_secret_hex)
    if len(pairing_secret) <= 16:
        raise PairingError("Sunshine returned an unexpectedly short pairingsecret")
    server_secret = pairing_secret[:16]
    server_signature = pairing_secret[16:]

    verify_server_signature(server_cert_pem, server_secret, server_signature)
    server_cert_signature = x509.load_pem_x509_certificate(server_cert_pem).signature
    expected_server_hash = sha256_bytes(
        client_challenge, server_cert_signature, server_secret
    )
    server_hash_matches = expected_server_hash == server_hash

    client_signature = sign_with_client_key(identity.private_key_pem, client_secret)
    phase4 = pair_request(
        session,
        args.host,
        args.http_port,
        {
            "uniqueid": identity.unique_id,
            "uuid": random_uuid_hex(),
            "clientpairingsecret": hex_encode(client_secret + client_signature),
        },
        timeout_seconds=30,
    )

    paired_value = child_text(phase4, "paired")
    if paired_value != "1":
        raise PairingError(
            f"Sunshine reported pairing failure: paired={paired_value!r}"
        )

    metadata: dict[str, Any] = {
        "pairedAt": datetime.now(UTC).isoformat(),
        "host": args.host,
        "httpPort": args.http_port,
        "httpsPort": https_port,
        "deviceName": args.name,
        "clientUniqueId": identity.unique_id,
        "appVersion": app_version,
        "gfeVersion": gfe_version,
        "serverCodecModeSupport": codec_mode_support,
        "serverHashMatched": server_hash_matches,
        "paths": {
            "clientCert": artifacts.cert_path.name,
            "clientKey": artifacts.key_path.name,
            "serverCert": artifacts.server_cert_path.name,
        },
    }

    persist_artifacts(artifacts, identity, server_cert_pem, metadata)

    verify_summary = None
    if not args.skip_verify_check:
        verify_root = https_verify_pairing(
            host=args.host,
            https_port=https_port,
            unique_id=identity.unique_id,
            cert_path=artifacts.cert_path,
            key_path=artifacts.key_path,
        )
        verify_summary = {
            "pairStatus": child_text(verify_root, "PairStatus"),
            "currentGame": child_text(verify_root, "currentgame"),
            "state": child_text(verify_root, "state"),
        }
        metadata["httpsVerification"] = verify_summary
        artifacts.metadata_path.write_text(
            json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
        )

    print("Pairing completed.")
    print(f"Artifacts written to: {artifacts.output_dir}")
    print(f"  client cert:  {artifacts.cert_path}")
    print(f"  client key:   {artifacts.key_path}")
    print(f"  server cert:  {artifacts.server_cert_path}")
    print(f"  metadata:     {artifacts.metadata_path}")
    if not server_hash_matches:
        print(
            "Warning: local server hash verification did not match; keeping artifacts for debugging anyway."
        )
    if verify_summary is not None:
        print(
            f"HTTPS verification: PairStatus={verify_summary['pairStatus']} state={verify_summary['state']}"
        )

    print()
    print("To remove all generated state from this helper, delete:")
    print(f"  rm -rf {artifacts.output_dir}")
    return 0


def main() -> int:
    try:
        return run()
    except requests.RequestException as exc:
        print(f"Network error: {exc}", file=sys.stderr)
        return 1
    except PairingError as exc:
        print(f"Pairing failed: {exc}", file=sys.stderr)
        return 1
    except Exception as exc:  # pragma: no cover - emergency fallback for manual tooling
        print(f"Unexpected error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
