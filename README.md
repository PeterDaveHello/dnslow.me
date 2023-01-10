# dnslow.me

Your advertisement and threat blocking, privacy-first, encrypted DNS.

All DNS requests will be protected with [threat-intelligence feeds](https://github.com/PeterDaveHello/threat-hostlist), [Newly Registered Domain](https://github.com/PeterDaveHello/nrd-list-downloader) feeds(paid feed included), AD-blocking feeds, and then randomly distributed to some other DNS resolvers for enhanced privacy.

Only DoH(DNS over HTTPS), DoT(DNS over TLS), and DoQ(DNS over Quic) protocol are provided, plain-text DNS is not supported here.

Encrypted DNS Endpoints:

- DoH: `https://dnslow.me/dns-query` (port 443).
- DoT: `dnslow.me` (port 853)
- DoQ: `dnslow.me` (port 853)

DNS Stamps(For AdGuard Home, DNSCrypt, and other compatiple applications):

- DoH: `sdns://AgEAAAAAAAAAAAAJZG5zbG93Lm1lCi9kbnMtcXVlcnk`
- DoT: `sdns://AwEAAAAAAAAAAAAJZG5zbG93Lm1l`
- DoQ: `sdns://BAEAAAAAAAAAAAAJZG5zbG93Lm1l`

Privacy policy: Logging is only enabled to debug, and improve the service itself, minimize the false-positive blocking. All logs will only be existing for a very short time. No logs will be shared, sold, or exchanged with any 3rd-party.

Thank you for using dnslow.me.
