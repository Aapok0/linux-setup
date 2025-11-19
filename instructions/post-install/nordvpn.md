# NordVPN setup

## Login

```bash
nordvpn login --token "<token_from_account_here>"
```

- Does not automatically return to terminal afterwards -> copy link from continue button

```bash
nordvpn login --callback "<nordvpnlink>"
```

## Enable NordLynx

```bash
nordvpn set technology nordlynx
```

## Setup basic connection settings

```bash
nordvpn set protocol UDP
nordvpn killswitch disabled
nordvpn set dns 103.86.96.100 103.86.99.100
```

## Set autoconnect location

```bash
nordvpn set autoconnect on Finland
```

## Enable Threat Protection Lite (this or nordvpn dns)

```bash
nordvpn set threatprotectionlite enabled
```
