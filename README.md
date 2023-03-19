# dnslow.me

Your privacy-first, encrypted DNS service that blocks advertisements and threats.

dnslow.me offers a secure, encrypted DNS service with integrated ad-blocking and protection against a wide range of online threats, including malicious domains, phishing sites, malware, ransomware, botnets, and high-risk newly registered domains (NRDs). Designed with a focus on user privacy and security.

All DNS requests are protected using [threat-intelligence feeds](https://github.com/PeterDaveHello/threat-hostlist), [Newly Registered Domain](https://github.com/PeterDaveHello/nrd-list-downloader) feeds (including paid feeds), and ad-blocking feeds. The requests are then randomly distributed to other DNS resolvers to further enhance privacy.

We are committed to user privacy and security, exclusively supporting encrypted DNS protocols, including DoH (DNS over HTTPS), DoT (DNS over TLS), and DoQ (DNS over QUIC). Plain-text DNS is not supported.

## Encrypted DNS Endpoints:

- DoH: `https://dnslow.me/dns-query` (port 443).
- DoT: `dnslow.me` (port 853)
- DoQ: `dnslow.me` (port 853)

## DNS Stamps (for AdGuard Home, DNSCrypt, and other compatible applications):

- DoH: `sdns://AgEAAAAAAAAAAAAJZG5zbG93Lm1lCi9kbnMtcXVlcnk`
- DoT: `sdns://AwEAAAAAAAAAAAAJZG5zbG93Lm1l`
- DoQ: `sdns://BAEAAAAAAAAAAAAJZG5zbG93Lm1l`

## Encrypted DNS Configuration Guides

Please be aware that the configuration steps may vary slightly depending on your device and software version. If you encounter any issues, we recommend referring to the official documentation for your specific device or software.

### Android (v9+)

1. Go to `Settings` → `Network & internet` → `Advanced` → `Private DNS`.
2. Select the `Private DNS provider hostname` option.
3. Enter `dnslow.me` and tap on `Save`.

### Desktop Browsers

Open `Settings` from the menu, then follow the instructions below for different browsers.

#### Mozilla Firefox

1. In the `General` tab, scroll down to the `Network Settings` section and click on `Settings`.
2. Scroll down and enable `Enable DNS over HTTPS`.
3. Choose `Custom` as the provider and enter `https://dnslow.me/dns-query` in the field.
4. Click on `OK` to save the changes.

#### Brave

1. Click the `Privacy and security` tab, then click on `Security`.
2. In the `Advanced` section, enable `Use secure DNS`.
3. Under `With`, select `Custom`, then enter `https://dnslow.me/dns-query` in the field.

#### Google Chrome

1. Scroll down and click on `Privacy and security`, then click on `Security`.
2. In the `Advanced` section, enable `Use secure DNS`.
3. Under `With`, select `Custom`, then enter `https://dnslow.me/dns-query` in the field.

#### Microsoft Edge

1. Scroll down to `Privacy, Search, and Services`, then click on `Security`.
2. Enable `Use secure DNS` under the `Security` section.
3. Under `Choose a service provider`, select `Enter custom provider`and enter`https://dnslow.me/dns-query` in the field.

### Apple Devices

Download the Configuration Profile. If you are using an iOS device, make sure to download it via **Safari**. Then, follow the instructions below for different devices:

- [DoH profile](https://dnslow.me/doh.dnslow.mobileconfig)
- [DoT profile](https://dnslow.me/dot.dnslow.mobileconfig)

#### iOS (v14+)

1. Tap `Allow` if asked to allow download.
2. Open `Settings` app and tap to `Profile Downloaded`.
3. Tap `Install` in the upper right corner, fill in your password and follow the instructions to complete the installation.

#### macOS (v11+)

1. Open the downloaded profile.
2. Open `System Preferences`.
3. Go to `Profiles`(Use the Search function to locate it faster!).
4. Double click the downloaded profile and follow the instructions to complete the installation.

## Contact and Support

If you have any questions, concerns, or issues related to our DNS service, please feel free to open an issue on our [GitHub repository issue tracker](https://github.com/PeterDaveHello/dnslow.me/issues). We appreciate your feedback and will do our best to assist you.

## Privacy Policy

Logging is enabled only for debugging purposes, service improvement, and minimizing false-positive blocking. All logs are retained for a very short period and will not be shared, sold, or exchanged with any third party.

Thank you for using dnslow.me.
