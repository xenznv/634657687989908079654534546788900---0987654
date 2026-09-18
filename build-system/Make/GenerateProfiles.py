import json
import os
import sys
import shutil
import tempfile
import plistlib
import argparse
import subprocess
import base64

from BuildEnvironment import run_executable_with_output, check_run_system

# OpenSSL binary to use. Can be overridden with OPENSSL_BIN (e.g. Homebrew's
# OpenSSL 3 on macOS, whose system LibreSSL cannot parse legacy-encrypted p12 files).
OPENSSL = os.environ.get('OPENSSL_BIN', 'openssl')


def setup_temp_keychain(p12_path, p12_password=''):
    """Create a temporary keychain and import the p12 certificate."""
    keychain_name = 'generate-profiles-temp.keychain'
    keychain_password = 'temp123'

    # Delete if exists
    run_executable_with_output('security', arguments=['delete-keychain', keychain_name], check_result=False)

    # Create keychain
    run_executable_with_output('security', arguments=[
        'create-keychain', '-p', keychain_password, keychain_name
    ], check_result=True)

    # Add to search list
    existing = run_executable_with_output('security', arguments=['list-keychains', '-d', 'user'])
    run_executable_with_output('security', arguments=[
        'list-keychains', '-d', 'user', '-s', keychain_name, existing.replace('"', '')
    ], check_result=True)

    # Unlock and set settings
    run_executable_with_output('security', arguments=['set-keychain-settings', keychain_name])
    run_executable_with_output('security', arguments=[
        'unlock-keychain', '-p', keychain_password, keychain_name
    ])

    # Import p12
    run_executable_with_output('security', arguments=[
        'import', p12_path, '-k', keychain_name, '-P', p12_password,
        '-T', '/usr/bin/codesign', '-T', '/usr/bin/security'
    ], check_result=True)

    # Set partition list for access
    run_executable_with_output('security', arguments=[
        'set-key-partition-list', '-S', 'apple-tool:,apple:', '-k', keychain_password, keychain_name
    ], check_result=True)

    return keychain_name


def cleanup_temp_keychain(keychain_name):
    """Remove the temporary keychain."""
    run_executable_with_output('security', arguments=['delete-keychain', keychain_name], check_result=False)


def _openssl_extract_cert_pem(p12_path, p12_password=''):
    """Extract certificates from a p12 via OpenSSL, trying several flag combos.

    Returns the PEM bytes on success, None on failure (with the last stderr
    printed so the real cause is visible in CI logs).
    """
    attempts = [
        [OPENSSL, 'pkcs12', '-in', p12_path, '-passin', 'pass:' + p12_password, '-nokeys', '-legacy'],
        [OPENSSL, 'pkcs12', '-in', p12_path, '-passin', 'pass:' + p12_password, '-nokeys', '-provider', 'legacy', '-provider', 'default'],
        [OPENSSL, 'pkcs12', '-in', p12_path, '-passin', 'pass:' + p12_password, '-nokeys'],
    ]
    last_error = ''
    for cmd in attempts:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        cert_pem, err = proc.communicate()
        if proc.returncode == 0 and b'BEGIN CERTIFICATE' in cert_pem:
            return cert_pem
        tail = err.decode('utf-8', 'ignore').strip().splitlines()
        last_error = tail[-1] if tail else 'no output'
    print('Warning: OpenSSL could not read the p12 (last error: {})'.format(last_error))
    return None


def _security_export_cert_pem(p12_path, p12_password=''):
    """Fallback: let macOS `security` import the p12 and export the certificate.

    `security` parses legacy-encrypted p12 files natively, so this works even
    when the available OpenSSL build refuses them.
    """
    if sys.platform != 'darwin':
        return None
    keychain_name = 'p12-identity-probe.keychain'
    try:
        run_executable_with_output('security', arguments=['delete-keychain', keychain_name], check_result=False)
        run_executable_with_output('security', arguments=['create-keychain', '-p', 'probe123', keychain_name], check_result=True)
        run_executable_with_output('security', arguments=['import', p12_path, '-k', keychain_name, '-P', p12_password], check_result=True)
        pem = run_executable_with_output('security', arguments=['find-certificate', '-p', '-k', keychain_name], check_result=True)
        if pem and 'BEGIN CERTIFICATE' in pem:
            return pem.encode('utf-8')
        return None
    except Exception as e:
        print('Warning: `security` fallback failed: {}'.format(e))
        return None
    finally:
        run_executable_with_output('security', arguments=['delete-keychain', keychain_name], check_result=False)


def _cert_pem_for_p12(p12_path, p12_password=''):
    pem = _openssl_extract_cert_pem(p12_path, p12_password)
    if pem is None:
        pem = _security_export_cert_pem(p12_path, p12_password)
    return pem


def _common_name_from_pem(cert_pem):
    proc2 = subprocess.Popen(
        [OPENSSL, 'x509', '-noout', '-subject', '-nameopt', 'oneline,-esc_msb'],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    subject, _ = proc2.communicate(cert_pem)
    subject = subject.decode('utf-8').strip()

    # Parse CN from subject line like: subject= C = AE, O = ..., CN = Some Name
    for marker in ('CN = ', 'CN='):
        if marker in subject:
            cn = subject.split(marker)[-1].split(',')[0].strip()
            if cn:
                return cn
    return None


def get_signing_identity_from_p12(p12_path, p12_password=''):
    """Extract the common name (signing identity) from the p12 certificate."""
    cert_pem = _cert_pem_for_p12(p12_path, p12_password)
    if cert_pem is None:
        return None
    return _common_name_from_pem(cert_pem)


def get_certificate_base64_from_p12(p12_path, p12_password=''):
    """Extract the certificate as base64 from p12 file."""
    cert_pem = _cert_pem_for_p12(p12_path, p12_password)
    if cert_pem is None:
        print('Warning: could not extract certificate from p12')
        return ''

    # Convert to DER format
    proc2 = subprocess.Popen(
        [OPENSSL, 'x509', '-outform', 'DER'],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    cert_der, _ = proc2.communicate(cert_pem)

    return base64.b64encode(cert_der).decode('utf-8')


def process_provisioning_profile(source, destination, certificate_data, signing_identity, keychain_name):
    parsed_plist = run_executable_with_output('security', arguments=['cms', '-D', '-i', source], check_result=True)
    parsed_plist_file = tempfile.mktemp()
    with open(parsed_plist_file, 'w+') as file:
        file.write(parsed_plist)

    # Remove all existing developer certificates
    while True:
        result = run_executable_with_output('plutil', arguments=['-remove', 'DeveloperCertificates.0', parsed_plist_file], check_result=False)
        if result is None or 'Could not' in str(result) or result == '':
            # Check if the removal actually failed by trying to extract
            check = run_executable_with_output('plutil', arguments=['-extract', 'DeveloperCertificates.0', 'raw', parsed_plist_file], check_result=False)
            if check is None or 'Could not' in str(check):
                break

    # Insert the new certificate
    run_executable_with_output('plutil', arguments=['-insert', 'DeveloperCertificates.0', '-data', certificate_data, parsed_plist_file])

    # Remove the DER-Encoded-Profile (signature)
    run_executable_with_output('plutil', arguments=['-remove', 'DER-Encoded-Profile', parsed_plist_file])

    # Refresh the expiration date if it is in the past. The example profiles are long expired,
    # and rules_apple's plisttool refuses profiles whose ExpirationDate has passed. The date is
    # purely cosmetic once the profile is re-signed with our own certificate.
    try:
        expire_raw = run_executable_with_output('plutil', arguments=['-extract', 'ExpirationDate', 'raw', parsed_plist_file], check_result=False)
        if expire_raw:
            from datetime import datetime, timedelta
            expire_dt = datetime.strptime(expire_raw.strip().strip('"'), '%Y-%m-%dT%H:%M:%SZ')
            if expire_dt < datetime.now():
                new_date = (datetime.now() + timedelta(days=3650)).strftime('%Y-%m-%dT%H:%M:%SZ')
                run_executable_with_output('plutil', arguments=['-replace', 'ExpirationDate', '-date', new_date, parsed_plist_file])
                print('Refreshed ExpirationDate to {}'.format(new_date))
    except Exception as e:
        print('Warning: could not refresh ExpirationDate: {}'.format(e))

    # Sign with the certificate from the temporary keychain
    run_executable_with_output('security', arguments=[
        'cms', '-S', '-k', keychain_name, '-N', signing_identity, '-i', parsed_plist_file, '-o', destination
    ], check_result=True)

    os.unlink(parsed_plist_file)


def generate_provisioning_profiles(source_path, destination_path, certs_path):
    p12_path = os.path.join(certs_path, 'SelfSigned.p12')

    if not os.path.exists(p12_path):
        print('{} does not exist'.format(p12_path))
        sys.exit(1)

    if not os.path.exists(destination_path):
        print('{} does not exist'.format(destination_path))
        sys.exit(1)

    # Extract certificate info from p12
    p12_password = ''  # fake-codesigning uses empty password
    certificate_data = get_certificate_base64_from_p12(p12_path, p12_password)
    signing_identity = get_signing_identity_from_p12(p12_path, p12_password)

    if not signing_identity:
        print('Could not extract signing identity from {}'.format(p12_path))
        sys.exit(1)

    print('Using signing identity: {}'.format(signing_identity))

    # Setup temporary keychain with the certificate
    keychain_name = setup_temp_keychain(p12_path, p12_password)

    try:
        for file_name in os.listdir(source_path):
            if file_name.endswith('.mobileprovision'):
                print('Processing {}'.format(file_name))
                process_provisioning_profile(
                    source=os.path.join(source_path, file_name),
                    destination=os.path.join(destination_path, file_name),
                    certificate_data=certificate_data,
                    signing_identity=signing_identity,
                    keychain_name=keychain_name
                )
        print('Done. Generated {} profiles.'.format(
            len([f for f in os.listdir(destination_path) if f.endswith('.mobileprovision')])
        ))
    finally:
        cleanup_temp_keychain(keychain_name)
