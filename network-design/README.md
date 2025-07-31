# Network Infrastructure for location1.jasrco.com

## Network Specifications

| Network Name | Subnet           | Internet Access | Intra-Net Comm | Notes                     |
|--------------|------------------|-----------------|----------------|---------------------------|
| vpnnet       | 172.16.0.0/16    | Allowed         | Blocked        | Blocks internal traffic   |
| appnet2      | 172.17.0.0/16    | Allowed         | Allowed        |                           |
| appnet3      | 172.16.0.0/17    | Blocked         | Allowed        |                           |
| dbnet        | 172.18.0.0/16    | Blocked         | Allowed        |                           |

## Common Rules
- All networks block egress to 192.0.0.0/8
- Networks cannot communicate with each other
- Designed for multi-stack usage (attachable: true)

## Usage

1. Deploy networks:
```bash
docker compose -f dc.network.jascro.com.yaml up -d
```

2. Connect services:
```yaml
services:
  myservice:
    networks:
      - vpnnet
      - appnet2

networks:
  vpnnet:
    external: true
  appnet2:
    external: true
```

3. Validate setup:
```bash
chmod +x network-tests.sh
./network-tests.sh
```

## Repeating for Other Locations
To deploy this setup for a new location:
1. Copy `dc.network.jascro.com.yaml` to new location file
2. Update subnet ranges in the file
3. Run deployment command
4. Run validation tests
